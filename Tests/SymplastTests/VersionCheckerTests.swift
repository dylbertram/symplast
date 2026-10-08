import XCTest
@testable import Symplast

final class VersionCheckerTests: XCTestCase {
    func testVersionNormalizationAndOrdering() {
        XCTAssertEqual(VersionChecker.normalizedVersion("v1.2.3"), "1.2.3")
        XCTAssertEqual(VersionChecker.normalizedVersion("1.02.3"), "1.2.3")
        XCTAssertNil(VersionChecker.normalizedVersion("1.2"))
        XCTAssertNil(VersionChecker.normalizedVersion("1.2.3-beta.1"))
        XCTAssertNil(VersionChecker.normalizedVersion("1.2.999999999999999999999"))
        XCTAssertEqual(VersionChecker.compare("1.10.0", "1.9.9"), .orderedDescending)
        XCTAssertEqual(VersionChecker.compare("2.0.0", "2.0.0"), .orderedSame)
        XCTAssertEqual(VersionChecker.compare("1.9.9", "1.10.0"), .orderedAscending)
    }
}
