import XCTest

final class BrowserUserAgentTests: XCTestCase {
    func testRealSafariIdentityIsAdded() {
        let name = BrowserUserAgent.applicationName(systemVersion: "17.4.1")
        XCTAssertEqual(name, "Version/17.4 Safari/605.1.15")
        XCTAssertTrue(name.contains("Version/"))
        XCTAssertTrue(name.contains("Safari/"))
    }

    func testNeverClaimsAnotherEngine() {
        let name = BrowserUserAgent.applicationName(systemVersion: "18.2")
        XCTAssertFalse(name.localizedCaseInsensitiveContains("chrome"))
        XCTAssertFalse(name.contains("CriOS"))
        XCTAssertFalse(name.contains("Edg"))
        XCTAssertFalse(name.contains("Firefox"))
        XCTAssertFalse(name.contains("iPhone"))
        XCTAssertFalse(name.contains("Mobile"))
    }

    func testMinorVersionAndFallbackAreStable() {
        XCTAssertEqual(BrowserUserAgent.applicationName(systemVersion: "26"), "Version/26.0 Safari/605.1.15")
        XCTAssertEqual(BrowserUserAgent.applicationName(systemVersion: ""), "Version/17.0 Safari/605.1.15")
        XCTAssertEqual(BrowserUserAgent.applicationName(systemVersion: "18.1.2"),
                       BrowserUserAgent.applicationName(systemVersion: "18.1.2"))
    }
}
