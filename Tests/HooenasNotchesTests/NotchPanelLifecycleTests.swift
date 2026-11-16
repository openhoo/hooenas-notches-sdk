import AppKit
import SwiftUI
import XCTest

@testable import HooenasNotches

@MainActor
final class NotchPanelLifecycleTests: XCTestCase {
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

        controller.update(content: EditorContent(probe: probe), screen: screen, isExpanded: { true })
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(window.contentView === originalHosting, "A content refresh must keep its native hosting view")
        XCTAssertTrue(probe.editor === originalEditor, "The same SwiftUI content type must retain its native editor")
        XCTAssertTrue(window.firstResponder === originalResponder, "A content refresh must not steal keyboard focus")
        XCTAssertEqual(probe.creationCount, 1)
        XCTAssertEqual(probe.editor?.stringValue, "An unfinished note")

        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(window.contentView === originalHosting, "A display change must also preserve the active editor")
        XCTAssertTrue(window.firstResponder === originalResponder)
        let updatedLayout = try XCTUnwrap(controller.layoutSnapshot)
        XCTAssertEqual(updatedLayout.panelFrame.maxY, updatedLayout.screenFrame.maxY, accuracy: 0.5)
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
