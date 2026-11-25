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

    func testExplicitlyFocusedPanelCanCollapseWithoutAnEditableControl() async throws {
        _ = NSApplication.shared
        guard NSScreen.screens.first != nil else { throw XCTSkip("Requires a desktop display") }
        let state = KeyboardState(expanded: true)
        let controller = NotchPanelController()
        defer { controller.hide() }
        controller.show(
            isExpanded: Binding(get: { state.expanded }, set: { state.expanded = $0 }), hoverOpens: false
        ) {
            Text("Summary")
        } expanded: {
            Text("Read-only details")
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(controller.focus())
        let window = try XCTUnwrap(NSApplication.shared.keyWindow)
        let focus = panelFocusDescription(window)
        try dispatchEscape(to: window)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(
            state.expanded, "Escape should work immediately after a menu or shortcut opens the panel (\(focus))")
    }

    func testComposedPanelCanCollapseWithOnlyWindowFocus() async throws {
        _ = NSApplication.shared
        guard NSScreen.screens.first != nil else { throw XCTSkip("Requires a desktop display") }
        let state = KeyboardState(expanded: true)
        let controller = NotchPanelController()
        defer { controller.hide() }
        controller.show(
            content: VStack {
                HooenasNotch(
                    isExpanded: Binding(get: { state.expanded }, set: { state.expanded = $0 }), hoverOpens: false
                ) {
                    Text("Summary")
                } expanded: {
                    Text("Read-only details")
                }
            }.onExitCommand { state.hostCancelCount += 1 },
            isExpanded: { state.expanded }
        )
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(controller.focus())
        let window = try XCTUnwrap(NSApp.keyWindow)
        XCTAssertTrue(window.makeFirstResponder(nil))
        XCTAssertTrue(window.firstResponder === window)
        try dispatchEscape(to: window)
        XCTAssertFalse(state.expanded)
        XCTAssertEqual(state.hostCancelCount, 0)
    }

    func testNativeEditorKeepsEscapeDuringTextComposition() async throws {
        _ = NSApplication.shared
        guard NSScreen.screens.first != nil else { throw XCTSkip("Requires a desktop display") }
        let state = KeyboardState(expanded: true)
        let controller = NotchPanelController()
        defer { controller.hide() }
        let editor = CompositionEditor()
        controller.show(
            isExpanded: Binding(get: { state.expanded }, set: { state.expanded = $0 }), hoverOpens: false
        ) {
            Text("Summary")
        } expanded: {
            EmbeddedEditor(editor: editor)
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(controller.focus())
        let window = try XCTUnwrap(editor.window)
        XCTAssertTrue(window.makeFirstResponder(editor))
        editor.setMarkedText(
            "ka", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        try dispatchEscape(to: window)
        XCTAssertTrue(editor.cancelledComposition, "The text input client must receive its own Escape")
        XCTAssertTrue(state.expanded)
    }

    func testTransientPopoverKeepsEscapeAheadOfItsNotch() async throws {
        _ = NSApplication.shared
        guard NSScreen.screens.first != nil else { throw XCTSkip("Requires a desktop display") }
        let state = KeyboardState(expanded: true)
        let controller = NotchPanelController()
        defer { controller.hide() }
        controller.show(
            isExpanded: Binding(get: { state.expanded }, set: { state.expanded = $0 }), hoverOpens: false
        ) {
            Text("Summary")
        } expanded: {
            Text("Read-only details")
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(controller.focus())
        let parent = try XCTUnwrap(NSApp.keyWindow)
        let anchor = try XCTUnwrap(parent.contentView)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: Text("Details").padding())
        defer { popover.close() }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        XCTAssertTrue(popover.isShown)
        let recipient = try XCTUnwrap(NSApp.keyWindow)
        try dispatchEscape(to: recipient)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(state.expanded, "Dismissing transient content must leave its parent notch open")
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
        try dispatchEscape(to: window)
        try await Task.sleep(for: .milliseconds(50))
    }

    private func panelFocusDescription(_ window: NSWindow) -> String {
        var views = window.contentView.map { [$0] } ?? []
        var markers = 0
        while let next = views.popLast() {
            guard !next.isHidden else { continue }
            if let marker = next as? NotchFocusMarker, marker.collapse != nil { markers += 1 }
            views.append(contentsOf: next.subviews)
        }
        let responder = window.firstResponder
        let name = responder.map { String(describing: type(of: $0)) } ?? "none"
        return "key=\(window.isKeyWindow), responder=\(name), window=\(responder === window), "
            + "host=\(responder === window.contentView), expanded markers=\(markers), allows escape=\(window.allowsNotchEscape)"
    }

    private func dispatchEscape(to window: NSWindow) throws {
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false, keyCode: 53
            ))
        NSApplication.shared.sendEvent(event)
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

private struct EmbeddedEditor: NSViewRepresentable {
    let editor: CompositionEditor
    func makeNSView(context: Context) -> CompositionEditor { editor }
    func updateNSView(_ nsView: CompositionEditor, context: Context) {}
}

private final class CompositionEditor: NSTextView {
    var cancelledComposition = false
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 && hasMarkedText() {
            cancelledComposition = true
            unmarkText()
        } else {
            super.keyDown(with: event)
        }
    }
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
