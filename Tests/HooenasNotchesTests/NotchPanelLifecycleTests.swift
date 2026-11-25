import AppKit
import SwiftUI
import XCTest

@testable import HooenasNotches

@MainActor
final class NotchPanelLifecycleTests: XCTestCase {
    func testPanelTracksStationaryPointerOnlyWhereExpansionCanChangeTheTarget() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("Requires a desktop display") }
        let probe = PointerProbe()
        probe.pointer = CGPoint(x: screen.frame.midX, y: screen.frame.minY)
        let controller = NotchPanelController(mouseLocation: { probe.pointer })
        defer { controller.hide() }
        let expansion: @MainActor () -> Bool = {
            probe.samples += 1
            return probe.expanded
        }

        controller.show(content: Color.clear, screen: screen, isExpanded: expansion)
        let layout = try XCTUnwrap(controller.layoutSnapshot)
        let window = try XCTUnwrap(NSApplication.shared.windows.first { $0.frame == layout.panelFrame })
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertEqual(probe.samples, 0, "An idle overlay must not sample client state while the pointer is elsewhere")

        probe.pointer = CGPoint(x: screen.frame.midX, y: screen.frame.maxY - 100)
        controller.update(content: Color.clear, screen: screen, isExpanded: expansion)
        XCTAssertTrue(window.ignoresMouseEvents)
        probe.expanded = true
        let deadline = ContinuousClock.now + .seconds(1)
        while window.ignoresMouseEvents && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(
            window.ignoresMouseEvents, "Programmatic expansion under a stationary pointer must accept clicks")
    }

    func testUpdatingContentPreservesNativeViewAndEditingFocus() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("Requires a desktop display") }
        let controller = NotchPanelController()
        defer { controller.hide() }
        let probe = EditorProbe()
        controller.show(content: EditorContent(probe: probe), screen: screen, isExpanded: { true })
        try await Task.sleep(for: .milliseconds(50))
        let layout = try XCTUnwrap(controller.layoutSnapshot)
        let window = try XCTUnwrap(NSApplication.shared.windows.first { $0.frame == layout.panelFrame })
        let originalHosting = try XCTUnwrap(window.contentView)
        let originalEditor = try XCTUnwrap(probe.editor)
        XCTAssertTrue(window.makeFirstResponder(originalEditor))
        let originalResponder = try XCTUnwrap(window.firstResponder)
        originalEditor.stringValue = "An unfinished note"

        controller.update(
            content: EditorContent(probe: probe),
            configuration: NotchConfiguration(expandedSize: CGSize(width: 420, height: 270)),
            screen: screen, isExpanded: { true }
        )
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(window.contentView === originalHosting, "A content refresh must keep its native hosting view")
        XCTAssertTrue(probe.editor === originalEditor, "The same SwiftUI content type must retain its native editor")
        XCTAssertTrue(window.firstResponder === originalResponder, "A content refresh must not steal keyboard focus")
        XCTAssertEqual(probe.creationCount, 1)
        XCTAssertEqual(probe.editor?.stringValue, "An unfinished note")
        XCTAssertEqual(controller.configuration.expandedSize, CGSize(width: 420, height: 270))

        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(window.contentView === originalHosting, "A display change must also preserve the active editor")
        XCTAssertTrue(window.firstResponder === originalResponder)
        let updatedLayout = try XCTUnwrap(controller.layoutSnapshot)
        XCTAssertEqual(updatedLayout.panelFrame.maxY, updatedLayout.screenFrame.maxY, accuracy: 0.5)
    }

    func testOversizedPanelRemainsOnScreenAndCanReceiveRequestedKeyboardFocus() throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("Requires a desktop display") }
        let controller = NotchPanelController()
        defer { controller.hide() }
        XCTAssertFalse(controller.focus())
        controller.show(
            configuration: NotchConfiguration(expandedSize: CGSize(width: 100_000, height: 40_000)),
            screen: screen, isExpanded: .constant(true), hoverOpens: false
        ) {
            Text("Example status")
        } expanded: {
            Text("Example content")
        }
        let layout = try XCTUnwrap(controller.layoutSnapshot)
        XCTAssertEqual(layout.panelFrame.midX, screen.frame.midX, accuracy: 0.5)
        XCTAssertEqual(layout.panelFrame.maxY, screen.frame.maxY, accuracy: 0.5)
        XCTAssertLessThanOrEqual(layout.panelFrame.width, screen.frame.width + 0.5)
        XCTAssertLessThanOrEqual(layout.panelFrame.height, screen.frame.height + 0.5)
        let window = try XCTUnwrap(NSApplication.shared.windows.first { $0.frame == layout.panelFrame })
        XCTAssertFalse(window.isKeyWindow, "Showing the overlay must leave the present key window unchanged")
        XCTAssertTrue(controller.focus())
        XCTAssertTrue(window.isKeyWindow)
    }

    func testHideReleasesExpansionCallbackCaptures() throws {
        _ = NSApplication.shared
        let controller = NotchPanelController()
        weak var releasedState: ExpansionState?
        do {
            let state = ExpansionState()
            releasedState = state
            controller.show(content: Color.clear, isExpanded: { state.expanded })
            controller.hide()
        }
        XCTAssertNil(releasedState, "A hidden controller must release callbacks from its previous presentation")
    }

    func testHideReleasesContentEvenWhileAppKitHostingViewIsRetained() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("Requires a desktop display") }
        let controller = NotchPanelController()
        defer { controller.hide() }
        weak var releasedState: HostedState?
        do {
            let state = HostedState()
            releasedState = state
            controller.show(content: HostedStateView(state: state), screen: screen)
        }
        let layout = try XCTUnwrap(controller.layoutSnapshot)
        let window = try XCTUnwrap(NSApplication.shared.windows.first { $0.frame == layout.panelFrame })
        let hosting = try XCTUnwrap(window.contentView)
        try await Task.sleep(for: .milliseconds(100))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertNotNil(releasedState)

        controller.hide()
        let deadline = ContinuousClock.now + .seconds(1)
        while releasedState != nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        withExtendedLifetime(hosting) {
            XCTAssertNil(releasedState, "Retained AppKit hosting views must not keep hidden notch content alive")
        }
    }
}

@MainActor
private final class PointerProbe {
    var pointer: CGPoint = .zero
    var expanded = false
    var samples = 0
}

@MainActor
private final class EditorProbe {
    weak var editor: NSTextField?
    var creationCount = 0
}

private struct EditorContent: NSViewRepresentable {
    let probe: EditorProbe

    func makeNSView(context: Context) -> NSTextField {
        let editor = NSTextField(string: "")
        editor.isEditable = true
        probe.editor = editor
        probe.creationCount += 1
        return editor
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}
}

private final class ExpansionState {
    var expanded = true
}

@MainActor
private final class HostedState: ObservableObject {
    @Published var title = "Notch content"
}

private struct HostedStateView: View {
    @ObservedObject var state: HostedState

    var body: some View { Text(state.title) }
}
