import XCTest

final class VersionCompareTests: XCTestCase {
    func testNumericOrdering() {
        XCTAssertTrue(VersionCompare.isNewer("0.6.10", than: "0.6.9"))
        XCTAssertFalse(VersionCompare.isNewer("0.6.9", than: "0.6.10"))
        XCTAssertTrue(VersionCompare.isNewer("1.3.0", than: "1.2.9"))
    }

    func testPrereleaseDoesNotSortAboveStable() {
        XCTAssertFalse(VersionCompare.isNewer("1.3.0-beta.1", than: "1.3.0"))
        XCTAssertFalse(VersionCompare.isNewer("1.3.0", than: "1.3.0-beta.1"))
        XCTAssertTrue(VersionCompare.isNewer("1.3.1-beta.1", than: "1.3.0"))
    }
}
