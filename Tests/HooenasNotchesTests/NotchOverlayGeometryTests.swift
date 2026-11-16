import XCTest

@testable import HooenasNotches

final class NotchOverlayGeometryTests: XCTestCase {
    func testContourRadiiStayInsideShallowBounds() {
        let bounds = CGRect(x: 17, y: 23, width: 320, height: 24)
        let rendered = ContourNotchShape(top: 200, bottom: 200).path(in: bounds).boundingRect
        XCTAssertGreaterThanOrEqual(rendered.minX, bounds.minX)
        XCTAssertGreaterThanOrEqual(rendered.minY, bounds.minY)
        XCTAssertLessThanOrEqual(rendered.maxX, bounds.maxX)
        XCTAssertLessThanOrEqual(rendered.maxY, bounds.maxY)
    }

    func testExternalDisplayPlacementUsesItsOwnGlobalFrame() {
        let screen = CGRect(x: -1920, y: 320, width: 1920, height: 1080)
        let frame = NotchOverlayGeometry.panelFrame(
            screenFrame: screen,
            canvasSize: CGSize(width: 700, height: 300),
            topInset: 10
        )
        XCTAssertEqual(frame.midX, screen.midX)
        XCTAssertEqual(frame.maxY, screen.maxY - 10)
    }

    func testTransparentWindowMarginsDoNotCaptureMouse() {
        let frame = CGRect(x: 300, y: 500, width: 700, height: 300)
        let closed = CGSize(width: 204, height: 32)
        XCTAssertTrue(
            NotchOverlayGeometry.contains(
                screenPoint: CGPoint(x: frame.midX, y: frame.maxY - 16),
                panelFrame: frame, notchSize: closed, style: .contour
            ))
        XCTAssertFalse(
            NotchOverlayGeometry.contains(
                screenPoint: CGPoint(x: frame.minX + 1, y: frame.maxY - 10),
                panelFrame: frame, notchSize: closed, style: .contour
            ))
        XCTAssertFalse(
            NotchOverlayGeometry.contains(
                screenPoint: CGPoint(x: frame.midX, y: frame.maxY - 60),
                panelFrame: frame, notchSize: closed, style: .contour
            ))
    }

    func testConcaveShouldersPassMouseThroughWhileCenterRemainsClickable() {
        let frame = CGRect(x: 0, y: 0, width: 640, height: 300)
        let size = CGSize(width: 640, height: 219)
        XCTAssertFalse(
            NotchOverlayGeometry.contains(
                screenPoint: CGPoint(x: 2, y: frame.maxY - 18),
                panelFrame: frame, notchSize: size, style: .contour,
                topRadius: 22, bottomRadius: 28
            ))
        XCTAssertTrue(
            NotchOverlayGeometry.contains(
                screenPoint: CGPoint(x: 320, y: frame.maxY - 180),
                panelFrame: frame, notchSize: size, style: .contour,
                topRadius: 22, bottomRadius: 28
            ))
    }

    func testContourPreservesTopContactAndCameraWingsInShiftedBounds() {
        let bounds = CGRect(x: 17, y: 23, width: 332, height: 38)
        let path = ContourNotchShape().path(in: bounds)
        XCTAssertTrue(path.contains(CGPoint(x: bounds.midX, y: bounds.minY + 0.5)))
        XCTAssertTrue(path.contains(CGPoint(x: bounds.minX + 28, y: bounds.minY + 0.5)))
        XCTAssertTrue(path.contains(CGPoint(x: bounds.maxX - 28, y: bounds.minY + 0.5)))
        XCTAssertFalse(path.contains(CGPoint(x: bounds.minX + 2, y: bounds.minY + 12)))
        XCTAssertFalse(path.contains(CGPoint(x: bounds.maxX - 2, y: bounds.minY + 12)))
    }

    func testCapsuleRoundedCornerIsNotAnInvisibleHitTarget() {
        let frame = CGRect(x: 0, y: 0, width: 204, height: 100)
        XCTAssertFalse(
            NotchOverlayGeometry.contains(
                screenPoint: CGPoint(x: 1, y: 99), panelFrame: frame,
                notchSize: CGSize(width: 204, height: 32), style: .capsule
            ))
    }
}
