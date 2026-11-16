// Hooenas Notches. See LICENSE and THIRD_PARTY_NOTICES.md.
import AppKit
import SwiftUI

/// Pure placement helpers, also useful to hosts that provide their own window.
public enum NotchOverlayGeometry {
    public static func panelFrame(screenFrame: CGRect, canvasSize: CGSize, topInset: CGFloat = 0) -> CGRect {
        CGRect(
            x: screenFrame.midX - canvasSize.width / 2,
            y: screenFrame.maxY - topInset - canvasSize.height,
            width: canvasSize.width,
            height: canvasSize.height
        )
    }

    public static func contains(
        screenPoint: CGPoint,
        panelFrame: CGRect,
        notchSize: CGSize,
        style: NotchStyle,
        topRadius: CGFloat = 8,
        bottomRadius: CGFloat = 16
    ) -> Bool {
        // AppKit screen coordinates count upward. SwiftUI paths count downward.
        let local = CGPoint(
            x: screenPoint.x - panelFrame.midX + notchSize.width / 2,
            y: panelFrame.maxY - screenPoint.y
        )
        let bounds = CGRect(origin: .zero, size: notchSize)
        guard bounds.contains(local) else { return false }
        return NotchSilhouette(style: style, top: topRadius, bottom: bottomRadius)
            .path(in: bounds).contains(local)
    }
}

/// Runtime geometry for diagnosing physical screen attachment.
public struct NotchPanelLayoutSnapshot: Sendable {
    public let screenFrame: CGRect
    public let panelFrame: CGRect
    public let hostingFrame: CGRect
    public let hostingSafeAreaTop: CGFloat
    public let hostingSafeAreaDisabled: Bool
}

/// Presents a notch at the physical top edge of a display without activating its app.
/// The panel passes mouse events through everywhere outside the visible notch.
@MainActor
public final class NotchPanelController {
    public private(set) var isVisible = false
    public private(set) var configuration = NotchConfiguration()
    public private(set) var screen: NSScreen?

    public var layoutSnapshot: NotchPanelLayoutSnapshot? {
        guard let screen, let panel, let hosting = panel.contentView as? PassthroughHostingView else { return nil }
        return NotchPanelLayoutSnapshot(
            screenFrame: screen.frame, panelFrame: panel.frame,
            hostingFrame: hosting.frame, hostingSafeAreaTop: hosting.safeAreaInsets.top,
            hostingSafeAreaDisabled: hosting.safeAreaRegions.isEmpty
        )
    }

    private var panel: NotchPanel?
    private var style: NotchStyle = .contour
    private var expansion: @MainActor () -> Bool = { false }
    private var content = AnyView(EmptyView())
    private var timer: Timer?
    private var displayObserver: NSObjectProtocol?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var requestedConfiguration = NotchConfiguration()

    public init() {}

    /// Call again to replace a displayed notch's content, style or configuration.
    /// The expansion closure must report the same binding passed to `HooenasNotch`.
    public func show<Content: View>(
        content: Content,
        configuration: NotchConfiguration = NotchConfiguration(),
        style: NotchStyle = .contour,
        screen: NSScreen? = nil,
        isExpanded: @escaping @MainActor () -> Bool = { false }
    ) {
        self.content = AnyView(content)
        self.requestedConfiguration = configuration
        self.style = style
        self.expansion = isExpanded
        self.screen = screen ?? self.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard self.screen != nil else { return }

        if panel == nil {
            let window = NotchPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
            window.isMovable = false
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.acceptsMouseMovedEvents = true
            panel = window
        }
        reposition()
        isVisible = true
        updateHitTesting()
        panel?.orderFrontRegardless()
        beginTracking()
    }

    /// Refresh a visible overlay after changing its style, content or dimensions.
    public func update<Content: View>(
        content: Content,
        configuration: NotchConfiguration = NotchConfiguration(),
        style: NotchStyle = .contour,
        screen: NSScreen? = nil,
        isExpanded: @escaping @MainActor () -> Bool = { false }
    ) {
        show(content: content, configuration: configuration, style: style, screen: screen, isExpanded: isExpanded)
    }

    /// Remove the overlay and all event monitors. A later `show` reuses this controller.
    public func hide() {
        isVisible = false
        timer?.invalidate()
        timer = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        localMonitor = nil
        globalMonitor = nil
        displayObserver = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
        content = AnyView(EmptyView())
    }

    private func reposition() {
        guard let panel else { return }
        if let old = screen, NSScreen.screens.contains(where: { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == old.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber }) {
            screen = NSScreen.screens.first(where: { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == old.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber })
        } else {
            screen = NSScreen.main ?? NSScreen.screens.first
        }
        guard let screen else { hide(); return }
        let cameraWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            cameraWidth = max(0, right.minX - left.maxX)
        } else {
            cameraWidth = 0
        }
        configuration = requestedConfiguration.accommodating(
            cameraHousingWidth: cameraWidth,
            safeAreaHeight: screen.safeAreaInsets.top
        )
        let canvas = CGSize(
            width: max(configuration.expandedSize.width, configuration.collapsedSize.width) + 80,
            height: max(configuration.expandedSize.height, configuration.collapsedSize.height) + 64
        )
        let hosting = PassthroughHostingView(rootView: AnyView(
            self.content.environment(\.notchScreenConfiguration, self.configuration)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(.container)
        ))
        // A notch is deliberately inside the camera/menu-bar area. Neither AppKit
        // nor SwiftUI should inset or resize its fixed stage away from that edge.
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        hosting.frame = CGRect(origin: .zero, size: canvas)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.setFrame(
            NotchOverlayGeometry.panelFrame(
                screenFrame: screen.frame, canvasSize: canvas,
                topInset: style.topInset
            ),
            display: true
        )
        updateHitTesting()
    }

    private func updateHitTesting() {
        guard let panel else { return }
        let expanded = expansion()
        let pointer = NSEvent.mouseLocation
        // Allow the modest compact hover enlargement to remain interactive.
        var visible = configuration.size(expanded: expanded)
        if !expanded {
            visible.width *= 1.03
            visible.height *= 1.04
        }
        panel.ignoresMouseEvents = !NotchOverlayGeometry.contains(
            screenPoint: pointer,
            panelFrame: panel.frame,
            notchSize: visible,
            style: style,
            topRadius: expanded ? configuration.expandedTopRadius : configuration.collapsedTopRadius,
            bottomRadius: expanded ? configuration.expandedBottomRadius : configuration.collapsedBottomRadius
        )
    }

    private func beginTracking() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateHitTesting() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.updateHitTesting() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            Task { @MainActor in self?.updateHitTesting() }
        }
    }

    isolated deinit { hide() }
}

@MainActor
private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // AppKit otherwise clamps maxY to visibleFrame.maxY, placing the overlay
    // below the menu bar (38 points below the camera on the tested MacBook).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
private final class PassthroughHostingView: NSHostingView<AnyView> {
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
