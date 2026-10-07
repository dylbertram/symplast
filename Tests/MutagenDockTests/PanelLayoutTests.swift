import XCTest
@testable import MutagenDock

final class PanelLayoutTests: XCTestCase {
    func testSingleSessionIsContentSized() {
        XCTAssertEqual(height(sessions: 1), 174)
    }

    func testSavedSessionIsContentSized() {
        XCTAssertEqual(height(saved: 1), 156)
    }

    func testMixedSectionsIncludeSpacing() {
        XCTAssertEqual(height(sessions: 2, saved: 1), 354)
    }

    func testEmptyStateStillHasRoomForDaemonBanner() {
        XCTAssertEqual(height(), 226)
        XCTAssertEqual(height(daemonAvailable: false), 326)
    }

    func testErrorOnlyAddsHeightWhenDisplayed() {
        XCTAssertEqual(height(sessions: 1, hasError: true), 226)
        XCTAssertEqual(height(daemonAvailable: false, hasError: true), 326)
    }

    func testManySessionsAreCappedForScrolling() {
        XCTAssertEqual(height(sessions: 100, saved: 100, hasError: true), 620)
    }

    func testSixLiveSessionsFitWithoutScrolling() {
        XCTAssertEqual(height(sessions: 6), 614)
        XCTAssertEqual(height(sessions: 6, saved: 1), 620)
    }

    private func height(sessions: Int = 0, saved: Int = 0,
                        daemonAvailable: Bool = true, hasError: Bool = false) -> CGFloat {
        Layout.listHeight(sessionCount: sessions, savedCount: saved,
                          daemonAvailable: daemonAvailable, hasError: hasError)
    }
}
