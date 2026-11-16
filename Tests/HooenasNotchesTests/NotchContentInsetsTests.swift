import XCTest

@testable import HooenasNotches

final class NotchContentInsetsTests: XCTestCase {
    func testExpandedContentGetsDefaultBreathingRoom() {
        let insets = NotchConfiguration().contentInsets
        XCTAssertEqual(insets.top, 44)
        XCTAssertEqual(insets.leading, 34)
        XCTAssertEqual(insets.bottom, 20)
        XCTAssertEqual(insets.trailing, 34)
    }

    func testCustomInsetsArePreservedWithoutPhysicalCamera() {
        let insets = NotchContentInsets(top: 0, leading: 8, bottom: 12, trailing: 16)
        let config = NotchConfiguration(contentInsets: insets)
            .accommodating(cameraHousingWidth: 0, safeAreaHeight: 0)
        XCTAssertEqual(config.contentInsets, insets)
    }

    func testCameraAddsOnlyNecessaryTopPaddingAndAllowsExplicitOptOut() {
        let insets = NotchContentInsets(top: 0, leading: 8, bottom: 12, trailing: 16)
        let config = NotchConfiguration(contentInsets: insets)
            .accommodating(cameraHousingWidth: 220, safeAreaHeight: 38)
        XCTAssertEqual(config.contentInsets, NotchContentInsets(top: 50, leading: 8, bottom: 12, trailing: 16))

        let unpadded = NotchConfiguration(contentInsets: insets, automaticallyPadsCamera: false)
            .accommodating(cameraHousingWidth: 220, safeAreaHeight: 38)
        XCTAssertEqual(unpadded.contentInsets, insets)

        let larger = NotchConfiguration(contentInsets: NotchContentInsets(top: 80))
            .accommodating(cameraHousingWidth: 220, safeAreaHeight: 38)
        XCTAssertEqual(larger.contentInsets.top, 80)
    }

    func testInvalidInsetsBecomeFiniteAndNonnegative() {
        let insets = NotchContentInsets(top: CGFloat.nan, leading: -5, bottom: CGFloat.infinity, trailing: -1)
        XCTAssertEqual(insets, NotchContentInsets(top: 44, leading: 0, bottom: 20, trailing: 0))
    }
}
