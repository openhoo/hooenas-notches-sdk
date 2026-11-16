import XCTest

@testable import HooenasNotches

final class NotchConfigurationTests: XCTestCase {
    func testMissingOrInvalidCameraMetricsPreserveCustomGeometry() {
        let compact = NotchConfiguration(collapsedSize: CGSize(width: 80, height: 48))
        XCTAssertEqual(compact.accommodating(cameraHousingWidth: 0, safeAreaHeight: 0), compact)

        let large = NotchConfiguration(collapsedSize: CGSize(width: 400, height: 64))
        XCTAssertEqual(large.accommodating(cameraHousingWidth: .infinity, safeAreaHeight: .infinity), large)
        XCTAssertEqual(large.accommodating(cameraHousingWidth: .nan, safeAreaHeight: .nan), large)
    }

    func testRejectsNonfiniteAndUndersizedGeometry() {
        let config = NotchConfiguration(
            collapsedSize: CGSize(width: CGFloat.nan, height: -1),
            expandedSize: CGSize(width: 1, height: CGFloat.infinity),
            collapsedTopRadius: -CGFloat.infinity
        )
        XCTAssertEqual(config.collapsedSize, CGSize(width: 204, height: 24))
        XCTAssertEqual(config.expandedSize, CGSize(width: 204, height: 219))
        XCTAssertTrue(config.collapsedTopRadius.isFinite)
        XCTAssertGreaterThanOrEqual(config.collapsedTopRadius, 0)
    }

    func testPhysicalCameraHousingEnlargesBothStatesWhenNeeded() {
        let config = NotchConfiguration(
            collapsedSize: CGSize(width: 204, height: 32),
            expandedSize: CGSize(width: 260, height: 100)
        ).accommodating(cameraHousingWidth: 300, safeAreaHeight: 38)
        XCTAssertEqual(config.collapsedSize, CGSize(width: 412, height: 38))
        XCTAssertGreaterThanOrEqual(config.expandedSize.width, config.collapsedSize.width)
        XCTAssertGreaterThanOrEqual(config.expandedSize.height, config.collapsedSize.height)
    }

    func testCameraAccommodationPreservesLargerCustomGeometry() {
        let config = NotchConfiguration(
            collapsedSize: CGSize(width: 400, height: 50),
            expandedSize: CGSize(width: 700, height: 260)
        )
        XCTAssertEqual(config.accommodating(cameraHousingWidth: 200, safeAreaHeight: 32), config)
    }
}
