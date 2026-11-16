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

    func testHostOnExitReceivesEscape() async throws {
        let state = KeyboardState(expanded: false)
        try await sendEscape(to: state, usesNotch: false)
        XCTAssertEqual(state.hostCancelCount, 1, "The plain SwiftUI host must handle Escape")
    }

    private func sendEscape(to state: KeyboardState, usesNotch: Bool = true) async throws {
        _ = NSApplication.shared
        guard NSScreen.screens.first != nil else { throw XCTSkip("Requires a desktop display") }
        let controller = NotchPanelController()
        defer { controller.hide() }
        controller.show(content: KeyboardContent(state: state, usesNotch: usesNotch), isExpanded: { state.expanded })
        try await Task.sleep(for: .milliseconds(100))
        let layout = try XCTUnwrap(controller.layoutSnapshot)
        let window = try XCTUnwrap(NSApplication.shared.windows.first { $0.frame == layout.panelFrame })
        let hosting = try XCTUnwrap(window.contentView)
        // Showing the nonactivating overlay does not make it key. Real keyboard
        // dispatch needs a key window even when makeFirstResponder succeeds.
        window.makeKey()
        XCTAssertTrue(window.isKeyWindow)
        XCTAssertTrue(NSApplication.shared.keyWindow === window)
        XCTAssertTrue(window.makeFirstResponder(hosting))
        XCTAssertTrue(window.firstResponder === hosting)
        hosting.layoutSubtreeIfNeeded()
        // AppKit container focus does not select a SwiftUI command target. Focus
        // real SwiftUI content so this is independent of full keyboard access.
        state.focusRequested = true
        let focusDeadline = ContinuousClock.now + .seconds(1)
        while (window.firstResponder as? NSTextView)?.isFieldEditor != true && ContinuousClock.now < focusDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        XCTAssertTrue(editor.isFieldEditor, "The SwiftUI text field must own keyboard focus before Escape")
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false, keyCode: 53
            ))
        NSApplication.shared.sendEvent(event)
        try await Task.sleep(for: .milliseconds(50))
    }
}

@MainActor
private final class KeyboardState: ObservableObject {
    @Published var expanded: Bool
    @Published var focusRequested = false
    @Published var text = ""
    var hostCancelCount = 0

    init(expanded: Bool) { self.expanded = expanded }
}

private struct KeyboardContent: View {
    @ObservedObject var state: KeyboardState
    var usesNotch = true
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if usesNotch {
                HooenasNotch(isExpanded: $state.expanded, hoverOpens: false) {
                    focusTarget("Task status")
                } expanded: {
                    focusTarget("Task controls")
                }
            } else {
                focusTarget("Plain host controls")
            }
        }
        .onExitCommand { state.hostCancelCount += 1 }
        .onChange(of: state.focusRequested) { _, requested in fieldFocused = requested }
    }

    private func focusTarget(_ title: String) -> some View {
        TextField(title, text: $state.text)
            .textFieldStyle(.plain)
            .focused($fieldFocused)
    }
}
