// Hooenas Notches. See LICENSE and THIRD_PARTY_NOTICES.md.
import AppKit
import SwiftUI

/// Pure placement helpers, also useful to hosts that provide their own window.
public enum NotchOverlayGeometry {
    // Transparent room for the shadow and compact hover transform. On a very
    // small display, spend that space on the notch before reserving the margins.
    static func canvasMargins(in bounds: CGSize) -> CGSize {
        CGSize(
            width: min(80, max(0, bounds.width - 160)),
            height: min(64, max(0, bounds.height - 80))
        )
    }

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
    /// The fitted configuration currently in use, including display and camera constraints.
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

    private let mouseLocation: @MainActor () -> CGPoint

    public convenience init() {
        self.init(mouseLocation: { NSEvent.mouseLocation })
    }

    init(mouseLocation: @escaping @MainActor () -> CGPoint) {
        self.mouseLocation = mouseLocation
    }

    /// Present a complete notch with one binding for the view and the panel's hit region.
    /// Call again with new settings to change geometry or appearance while visible.
    public func show<Compact: View, Expanded: View>(
        configuration: NotchConfiguration = NotchConfiguration(),
        style: NotchStyle = .contour,
        screen: NSScreen? = nil,
        isExpanded: Binding<Bool>,
        motion: NotchMotion = .spring,
        hoverOpens: Bool = true,
        accessibilityLabels: NotchAccessibilityLabels = NotchAccessibilityLabels(),
        @ViewBuilder compact: () -> Compact,
        @ViewBuilder expanded: () -> Expanded
    ) {
        show(
            content: HooenasNotch(
                style: style, isExpanded: isExpanded, configuration: configuration,
                motion: motion, hoverOpens: hoverOpens, accessibilityLabels: accessibilityLabels,
                compact: compact, expanded: expanded
            ),
            configuration: configuration, style: style, screen: screen, isExpanded: { isExpanded.wrappedValue }
        )
    }

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
        guard panel != nil else { return }
        isVisible = true
        beginTracking()
        updateHitTesting()
        panel?.orderFrontRegardless()
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

    /// Move keyboard focus to an already visible panel, for an explicit user action.
    @discardableResult
    public func focus() -> Bool {
        guard isVisible, let panel, panel.isVisible else { return false }
        panel.makeKey()
        return panel.isKeyWindow
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
        // AppKit may retain a detached hosting view. Clear its SwiftUI root so
        // a hidden notch does not keep client models or editor state alive.
        if let hosting = panel?.contentView as? PassthroughHostingView {
            hosting.rootView = AnyView(EmptyView())
            hosting.layoutSubtreeIfNeeded()
        }
        panel?.contentView = nil
        panel?.close()
        panel = nil
        content = AnyView(EmptyView())
        expansion = { false }
    }

    private func reposition() {
        guard let panel else { return }
        if let old = screen,
            NSScreen.screens.contains(where: {
                $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == old.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            })
        {
            screen = NSScreen.screens.first(where: {
                $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == old.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            })
        } else {
            screen = NSScreen.main ?? NSScreen.screens.first
        }
        guard let screen else {
            hide()
            return
        }
        let cameraWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            cameraWidth = max(0, right.minX - left.maxX)
        } else {
            cameraWidth = 0
        }
        let displaySize = CGSize(width: screen.frame.width, height: max(0, screen.frame.height - style.topInset))
        let margins = NotchOverlayGeometry.canvasMargins(in: displaySize)
        configuration = requestedConfiguration.fitting(
            in: CGSize(width: displaySize.width - margins.width, height: displaySize.height - margins.height),
            cameraHousingWidth: cameraWidth,
            safeAreaHeight: screen.safeAreaInsets.top
        )
        let canvas = CGSize(
            width: configuration.expandedSize.width + margins.width,
            height: configuration.expandedSize.height + margins.height
        )
        let rootView = AnyView(
            self.content.environment(\.notchScreenConfiguration, self.configuration)
                .environment(\.notchCameraHousingWidth, cameraWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(.container)
        )
        let hosting: PassthroughHostingView
        if let existing = panel.contentView as? PassthroughHostingView {
            // Updating the existing root preserves SwiftUI state, native editors
            // and first responder while the host refreshes progress or geometry.
            existing.rootView = rootView
            hosting = existing
        } else {
            hosting = PassthroughHostingView(rootView: rootView)
        }
        // A notch is deliberately inside the camera/menu-bar area. Neither AppKit
        // nor SwiftUI should inset or resize its fixed stage away from that edge.
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        hosting.frame = CGRect(origin: .zero, size: canvas)
        hosting.autoresizingMask = [.width, .height]
        if panel.contentView !== hosting { panel.contentView = hosting }
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
        let pointer = mouseLocation()
        let local = CGPoint(x: pointer.x - panel.frame.midX, y: panel.frame.maxY - pointer.y)
        let compact = configuration.collapsedSize
        let open = configuration.expandedSize
        let mightHit =
            abs(local.x) <= max(open.width, compact.width * 1.03) / 2 && local.y >= 0
            && local.y <= max(open.height, compact.height * 1.04)

        // Pointer events restart tracking on entry. Only poll a stationary pointer
        // where a host changing its expansion binding could actually change the target.
        // Keep the polling fallback if AppKit cannot install either movement monitor.
        if isVisible { setPolling(mightHit || localMonitor == nil || globalMonitor == nil) }
        guard mightHit else {
            if !panel.ignoresMouseEvents { panel.ignoresMouseEvents = true }
            return
        }
        let expanded = expansion()
        // Allow the modest compact hover enlargement to remain interactive.
        var visible = configuration.size(expanded: expanded)
        if !expanded {
            visible.width *= 1.03
            visible.height *= 1.04
        }
        let ignoresMouseEvents = !NotchOverlayGeometry.contains(
            screenPoint: pointer,
            panelFrame: panel.frame,
            notchSize: visible,
            style: style,
            topRadius: expanded ? configuration.expandedTopRadius : configuration.collapsedTopRadius,
            bottomRadius: expanded ? configuration.expandedBottomRadius : configuration.collapsedBottomRadius
        )
        if panel.ignoresMouseEvents != ignoresMouseEvents { panel.ignoresMouseEvents = ignoresMouseEvents }
    }

    private func setPolling(_ needed: Bool) {
        guard needed else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHitTesting() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func beginTracking() {
        guard displayObserver == nil else { return }
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

    override func sendEvent(_ event: NSEvent) {
        // Without a focused SwiftUI control, onExitCommand is not always dispatched.
        // Let real controls, text composition and transient windows handle their own Escape.
        if isKeyWindow, event.type == .keyDown, event.keyCode == 53,
            event.modifierFlags.intersection([.command, .control, .option, .shift, .function]).isEmpty,
            allowsNotchEscape,
            let hosting = contentView, firstResponder == nil || firstResponder === self || firstResponder === hosting,
            let collapse = singleExpandedNotch(in: hosting)
        {
            collapse()
            return
        }
        super.sendEvent(event)
    }

    private func singleExpandedNotch(in root: NSView) -> (@MainActor () -> Void)? {
        // Custom panel content can contain multiple notches. Only supply the fallback
        // when exactly one of them is expanded; leave ambiguous commands to the host.
        var result: (@MainActor () -> Void)?
        var views = [root]
        while let view = views.popLast() {
            guard !view.isHidden else { continue }
            if let action = (view as? NotchFocusMarker)?.collapse {
                guard result == nil else { return nil }
                result = action
            }
            views.append(contentsOf: view.subviews)
        }
        return result
    }

    // AppKit otherwise clamps maxY to visibleFrame.maxY, placing the overlay
    // below the menu bar (38 points below the camera on the tested MacBook).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

extension NSWindow {
    // A read-only popover can leave its parent panel key. Both the AppKit fallback
    // and SwiftUI's focused exit command must leave the presenting notch alone.
    var allowsNotchEscape: Bool {
        guard self is NotchPanel else { return true }
        return attachedSheet == nil && NSApp.modalWindow == nil && childWindows?.contains(where: \.isVisible) != true
    }
}

@MainActor
private final class PassthroughHostingView: NSHostingView<AnyView> {
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
