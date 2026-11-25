import AppKit
import SwiftUI
import XCTest

@testable import HooenasNotches

@MainActor
final class NotchHoverTests: XCTestCase {
    func testPendingHoverDoesNotTakeOwnershipOfAnExternalOpen() throws {
        let fixture = try HoverFixture()
        defer { fixture.close() }
        try fixture.deliverHover(true)
        // A shortcut or a menu command explicitly opens the notch during the hover delay.
        fixture.model.expanded = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertTrue(fixture.panel.makeFirstResponder(fixture.hosting))

        try fixture.hoverOutside()

        XCTAssertTrue(fixture.model.expanded, "Leaving the notch must not undo the explicit open")
    }

    func testPendingHoverExitDoesNotCloseAReopenedNotch() throws {
        let fixture = try HoverFixture()
        defer { fixture.close() }
        try fixture.hoverInside()
        XCTAssertTrue(fixture.panel.makeFirstResponder(fixture.hosting))
        try fixture.deliverHover(false)
        fixture.model.expanded = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        fixture.model.expanded = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        XCTAssertTrue(fixture.model.expanded, "A delayed exit from an earlier opening must not close the new one")
    }

    func testHoverExitKeepsActiveTextEditorOpen() throws {
        let fixture = try HoverFixture()
        defer { fixture.close() }
        try fixture.hoverInside()
        let editor = try XCTUnwrap(fixture.model.editor)
        XCTAssertTrue(fixture.panel.makeFirstResponder(editor))
        XCTAssertTrue(fixture.panel.firstResponder === editor)
        editor.insertText("A note being edited", replacementRange: NSRange(location: 0, length: 0))

        try fixture.hoverOutside()

        XCTAssertTrue(fixture.model.expanded, "Pointer exit must not remove content that owns keyboard focus")
        XCTAssertTrue(editor.window === fixture.panel, "The active editor must remain in the view hierarchy")
        XCTAssertTrue(fixture.panel.firstResponder === editor)
        XCTAssertEqual(editor.string, "A note being edited")
    }

    func testHoverExitKeepsActiveNativeFieldEditorOpen() throws {
        let fixture = try HoverFixture(usesFieldEditor: true)
        defer { fixture.close() }
        try fixture.hoverInside()
        let field = try XCTUnwrap(fixture.model.field)
        XCTAssertTrue(fixture.panel.makeFirstResponder(field))
        let editor = try XCTUnwrap(fixture.panel.firstResponder as? NSTextView)
        XCTAssertTrue(editor.isFieldEditor)
        XCTAssertTrue((editor.delegate as? NSTextField) === field)
        editor.insertText("An unfinished title", replacementRange: NSRange(location: 0, length: 0))

        try fixture.hoverOutside()

        XCTAssertTrue(fixture.model.expanded)
        XCTAssertTrue(field.window === fixture.panel)
        XCTAssertTrue(fixture.panel.firstResponder === editor)
        XCTAssertEqual(field.stringValue, "An unfinished title")
    }

    func testHoverExitClosesWhenOnlyHostingViewHasFocus() throws {
        let fixture = try HoverFixture()
        defer { fixture.close() }
        try fixture.hoverInside()
        XCTAssertTrue(fixture.panel.makeFirstResponder(fixture.hosting))

        try fixture.hoverOutside()

        XCTAssertFalse(fixture.model.expanded, "Container focus must not pin a hover-only expansion")
    }
}

@MainActor
private final class HoverFixture {
    let model: HoverModel
    let panel: HoverPanel
    let hosting: NSHostingView<HoverContent>

    init(usesFieldEditor: Bool = false) throws {
        _ = NSApplication.shared
        guard NSScreen.screens.first != nil else { throw XCTSkip("Requires a desktop display") }
        model = HoverModel(usesFieldEditor: usesFieldEditor)
        panel = HoverPanel(
            contentRect: CGRect(x: -5000, y: -5000, width: 760, height: 350),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        hosting = NSHostingView(rootView: HoverContent(model: model))
        hosting.frame = CGRect(x: 0, y: 0, width: 760, height: 350)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        panel.contentView = hosting
        panel.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        hosting.layoutSubtreeIfNeeded()
        hosting.updateTrackingAreas()
    }

    func hoverInside() throws {
        try deliverHover(true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertTrue(model.expanded, "The real SwiftUI hover callback must expand the notch")
    }

    func hoverOutside() throws {
        try deliverHover(false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    }

    func close() {
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
    }

    func deliverHover(_ inside: Bool) throws {
        // XCTest may add its own tracking area before SwiftUI's area.
        let area = try XCTUnwrap(hosting.trackingAreas.first { ($0.owner as? NSView) === hosting })
        let trackingNumber = Int(bitPattern: Unmanaged.passUnretained(area).toOpaque())
        let point = inside ? NSPoint(x: 380, y: 338) : NSPoint(x: 20, y: 20)
        let event = try XCTUnwrap(
            NSEvent.enterExitEvent(
                with: inside ? .mouseEntered : .mouseExited,
                location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 1,
                trackingNumber: trackingNumber, userData: nil
            ))
        XCTAssertTrue(event.trackingArea === area)
        if inside { hosting.mouseEntered(with: event) } else { hosting.mouseExited(with: event) }
    }
}

@MainActor
private final class HoverModel: ObservableObject {
    @Published var expanded = false
    let usesFieldEditor: Bool
    weak var editor: NSTextView?
    weak var field: NSTextField?

    init(usesFieldEditor: Bool) { self.usesFieldEditor = usesFieldEditor }
}

@MainActor
private final class HoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private struct HoverContent: View {
    @ObservedObject var model: HoverModel

    var body: some View {
        HooenasNotch(isExpanded: $model.expanded) {
            Text("Compact status")
        } expanded: {
            if model.usesFieldEditor {
                HoverField(model: model)
            } else {
                HoverEditor(model: model)
            }
        }
        .frame(width: 760, height: 350, alignment: .top)
    }
}

private struct HoverEditor: NSViewRepresentable {
    let model: HoverModel

    func makeNSView(context: Context) -> NSTextView {
        let editor = NSTextView()
        editor.isEditable = true
        model.editor = editor
        return editor
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {}
}

private struct HoverField: NSViewRepresentable {
    let model: HoverModel

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: "")
        model.field = field
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}
}
