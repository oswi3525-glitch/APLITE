import XCTest

final class GoogleSessionTests: XCTestCase {
    func testGoogleDomainMatching() {
        XCTAssertTrue(GoogleDomain.matches("accounts.google.com"))
        XCTAssertTrue(GoogleDomain.matches(".youtube.com"))
        XCTAssertTrue(GoogleDomain.matches("drive.google.com.vn"))
        XCTAssertFalse(GoogleDomain.matches("example.com"))
        XCTAssertFalse(GoogleDomain.matches("notgoogle.com.evil.test"))
    }
}
