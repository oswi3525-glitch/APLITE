import XCTest

final class BrowserUserAgentTests: XCTestCase {
    func testRealSafariIdentityIsAdded() {
        let name = BrowserUserAgent.applicationName(systemVersion: "27.0.1")
        XCTAssertEqual(name, "Version/27.0 Safari/605.1.15")
        XCTAssertTrue(name.contains("Version/"))
        XCTAssertTrue(name.contains("Safari/"))
    }

    func testNeverClaimsAnotherEngine() {
        let name = BrowserUserAgent.applicationName(systemVersion: "27.0")
        XCTAssertFalse(name.localizedCaseInsensitiveContains("chrome"))
        XCTAssertFalse(name.contains("CriOS"))
        XCTAssertFalse(name.contains("Edg"))
        XCTAssertFalse(name.contains("Firefox"))
        XCTAssertFalse(name.contains("iPhone"))
        XCTAssertFalse(name.contains("Mobile"))
    }

    func testMajorMinorAndRealFallback() {
        XCTAssertEqual(BrowserUserAgent.applicationName(systemVersion: "26"), "Version/26.0 Safari/605.1.15")
        XCTAssertEqual(BrowserUserAgent.applicationName(systemVersion: "18.1.2"),
                       "Version/18.1 Safari/605.1.15")
        XCTAssertEqual(BrowserUserAgent.applicationName(systemVersion: ""),
                       BrowserUserAgent.applicationNameFromProcessInfo())
    }
}
