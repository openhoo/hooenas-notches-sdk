import AppKit
import SwiftUI
import XCTest

@testable import HooenasNotches

@MainActor
final class NotchAccessibilityTests: XCTestCase {
    func testCompactButtonPreservesAccessibleContentDescription() async throws {
        _ = NSApplication.shared
        guard NSScreen.screens.first != nil else { throw XCTSkip("Requires a desktop display") }
        let baselineWindow = NSPanel(
            contentRect: CGRect(x: -5000, y: -5000, width: 320, height: 80),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        baselineWindow.isReleasedWhenClosed = false
        defer {
            baselineWindow.orderOut(nil)
            baselineWindow.contentView = nil
            baselineWindow.close()
        }
        let baseline = NSHostingView(rootView: Button("SwiftUI accessibility baseline") {})
        baseline.frame = CGRect(x: 0, y: 0, width: 320, height: 80)
        baselineWindow.contentView = baseline
        baselineWindow.orderBack(nil)
        try await Task.sleep(for: .milliseconds(100))
        baseline.layoutSubtreeIfNeeded()
        guard
            accessibleElements(in: baseline).contains(where: {
                attribute("accessibilityRole", of: $0) as? String == "AXButton"
            })
        else {
            throw XCTSkip(
                "This test process exposes no AX children for a plain SwiftUI Button; runtime accessibility comparison is unavailable"
            )
        }
        let controller = NotchPanelController()
        defer { controller.hide() }
        controller.show(
            content: HooenasNotch(isExpanded: .constant(false), hoverOpens: false) {
                Text("Upload 64 percent")
                    .accessibilityLabel("Upload progress, 64 percent")
            } expanded: {
                Text("Upload controls")
            })
        try await Task.sleep(for: .milliseconds(100))
        let layout = try XCTUnwrap(controller.layoutSnapshot)
        let window = try XCTUnwrap(NSApplication.shared.windows.first { $0.frame == layout.panelFrame })
        let hosting = try XCTUnwrap(window.contentView)
        hosting.layoutSubtreeIfNeeded()
        let elements = accessibleElements(in: hosting)
        let buttons = elements.filter { attribute("accessibilityRole", of: $0) as? String == "AXButton" }
        let labels = buttons.flatMap { element in
            ["accessibilityLabel", "accessibilityTitle"].compactMap { attribute($0, of: element) as? String }
        }
        XCTAssertTrue(
            labels.contains { $0.contains("Upload progress, 64 percent") },
            "Compact content must remain readable to assistive technology; found \(labels)")
    }

    private func accessibleElements(in root: NSObject) -> [NSObject] {
        var pending = [root]
        var result: [NSObject] = []
        var seen = Set<ObjectIdentifier>()
        while let element = pending.popLast() {
            guard seen.insert(ObjectIdentifier(element)).inserted else { continue }
            result.append(element)
            let children = attribute("accessibilityChildren", of: element) as? [NSObject] ?? []
            pending.append(contentsOf: children)
        }
        return result
    }

    private func attribute(_ name: String, of element: NSObject) -> Any? {
        let selector = NSSelectorFromString(name)
        guard element.responds(to: selector) else { return nil }
        return element.perform(selector)?.takeUnretainedValue()
    }
}
