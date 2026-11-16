import AppKit
import SwiftUI
import XCTest

@testable import HooenasNotches

@MainActor
final class NotchPanelAttachmentTests: XCTestCase {
    func testRenderedNotchSilhouetteStartsAtPhysicalTop() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("Requires a desktop display") }
        let controller = NotchPanelController()
        defer { controller.hide() }
        for style in NotchStyle.allCases {
            for expanded in [false, true] {
                controller.show(
                    content: HooenasNotch(style: style, isExpanded: .constant(expanded), hoverOpens: false) {
                        Color.clear
                    } expanded: {
                        Color.clear
                    },
                    style: style, screen: screen, isExpanded: { expanded }
                )
                // A reused hosting view animates between states; sample the final silhouette.
                try await Task.sleep(for: .milliseconds(750))
                let layout = try XCTUnwrap(controller.layoutSnapshot)
                let window = try XCTUnwrap(NSApplication.shared.windows.first { $0.frame == layout.panelFrame })
                let hosting = try XCTUnwrap(window.contentView)
                hosting.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let top = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 0))
                let bottom = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh - 1))
                let scale = CGFloat(bitmap.pixelsWide) / hosting.bounds.width
                // Sample beyond the default 28-point corner rather than its antialiased boundary.
                let wingOffset = controller.configuration.size(expanded: expanded).width / 2 - 34
                let left = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2 - Int(wingOffset * scale), y: 0))
                let right = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2 + Int(wingOffset * scale), y: 0))
                print(
                    "Notch rendered edge [\(style.rawValue), expanded=\(expanded)]: pixels=\(bitmap.pixelsWide)x\(bitmap.pixelsHigh) topAlpha=\(top.alphaComponent) wingAlphas=\(left.alphaComponent),\(right.alphaComponent) bottomAlpha=\(bottom.alphaComponent)"
                )
                XCTAssertGreaterThan(
                    top.alphaComponent, 0.5, "Visible silhouette must begin on the first physical-screen row")
                XCTAssertGreaterThan(left.alphaComponent, 0.5, "Left wing must meet the top edge beside the camera")
                XCTAssertGreaterThan(right.alphaComponent, 0.5, "Right wing must meet the top edge beside the camera")
                XCTAssertLessThan(bottom.alphaComponent, 0.05, "The transparent stage margin must stay below the notch")
            }
        }
    }

    func testEveryStyleTouchesPhysicalScreenTopWithoutHostingSafeArea() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("Requires a desktop display") }
        let controller = NotchPanelController()
        defer { controller.hide() }
        for style in NotchStyle.allCases {
            let probe = AttachmentProbe()
            controller.show(content: TopEdgeProbe(probe: probe).frame(height: 1), style: style, screen: screen)
            for _ in 0..<20 where probe.view?.window == nil {
                try await Task.sleep(for: .milliseconds(10))
            }
            let view = try XCTUnwrap(probe.view)
            view.window?.contentView?.layoutSubtreeIfNeeded()
            let window = try XCTUnwrap(view.window)
            let contentScreenFrame = window.convertToScreen(view.convert(view.bounds, to: nil))
            let layout = try XCTUnwrap(controller.layoutSnapshot)
            print(
                "Notch attachment [\(style.rawValue)]: screenTop=\(layout.screenFrame.maxY) panelTop=\(layout.panelFrame.maxY) SwiftUIContentTop=\(contentScreenFrame.maxY) safeAreaDisabled=\(layout.hostingSafeAreaDisabled)"
            )
            XCTAssertEqual(layout.panelFrame.maxY, screen.frame.maxY, accuracy: 0.5)
            XCTAssertEqual(contentScreenFrame.maxY, screen.frame.maxY, accuracy: 0.5)
            XCTAssertEqual(layout.hostingFrame.height, layout.panelFrame.height, accuracy: 0.5)
            XCTAssertTrue(layout.hostingSafeAreaDisabled)
        }
    }
}

@MainActor
private final class AttachmentProbe {
    weak var view: NSView?
}

private struct TopEdgeProbe: NSViewRepresentable {
    let probe: AttachmentProbe
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        probe.view = view
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        // A refresh may attach a new observation probe to the same native view.
        probe.view = nsView
    }
}
