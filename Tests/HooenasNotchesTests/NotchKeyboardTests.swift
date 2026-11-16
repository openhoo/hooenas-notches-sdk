import AppKit
import SwiftUI
import XCTest

@testable import HooenasNotches

@MainActor
final class NotchKeyboardTests: XCTestCase {
    func testCollapsedNotchLeavesEscapeToHost() async throws {
        let state = KeyboardState(expanded: false)
        try await sendEscape(to: state)
        XCTAssertEqual(state.hostCancelCount, 1, "A collapsed notch must not consume its host's cancel command")
        XCTAssertFalse(state.expanded)
    }

    func testExpandedNotchConsumesEscape() async throws {
        let state = KeyboardState(expanded: true)
        try await sendEscape(to: state)
        XCTAssertEqual(state.hostCancelCount, 0)
        XCTAssertFalse(state.expanded, "Escape must collapse an expanded notch")
    }

    private func sendEscape(to state: KeyboardState) async throws {
        _ = NSApplication.shared
        guard NSScreen.screens.first != nil else { throw XCTSkip("Requires a desktop display") }
        let controller = NotchPanelController()
        defer { controller.hide() }
        controller.show(content: KeyboardContent(state: state), isExpanded: { state.expanded })
        try await Task.sleep(for: .milliseconds(100))
        let layout = try XCTUnwrap(controller.layoutSnapshot)
        let window = try XCTUnwrap(NSApplication.shared.windows.first { $0.frame == layout.panelFrame })
        let hosting = try XCTUnwrap(window.contentView)
        XCTAssertTrue(window.makeFirstResponder(hosting))
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false, keyCode: 53
            ))
        hosting.keyDown(with: event)
        try await Task.sleep(for: .milliseconds(50))
    }
}

@MainActor
private final class KeyboardState: ObservableObject {
    @Published var expanded: Bool
    var hostCancelCount = 0

    init(expanded: Bool) { self.expanded = expanded }
}

private struct KeyboardContent: View {
    @ObservedObject var state: KeyboardState

    var body: some View {
        HooenasNotch(isExpanded: $state.expanded, hoverOpens: false) {
            Text("Task status")
        } expanded: {
            Text("Task controls")
        }
        .onExitCommand { state.hostCancelCount += 1 }
    }
}
