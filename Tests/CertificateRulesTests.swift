import XCTest

final class CertificateRulesTests: XCTestCase {
    func testRecognizesP12AndPfxCaseInsensitively() {
        XCTAssertTrue(CertificateRules.isSupported("p12"))
        XCTAssertTrue(CertificateRules.isSupported("PFX"))
        XCTAssertFalse(CertificateRules.isSupported("ipa"))
        XCTAssertFalse(CertificateRules.isSupported("mobileprovision"))
    }

    func testPasswordLabelCleanup() {
        XCTAssertEqual(CertificateRules.cleanPassword("Password: abc123"), "abc123")
        XCTAssertEqual(CertificateRules.cleanPassword("pass = secret"), "secret")
        XCTAssertEqual(CertificateRules.cleanPassword("  plainvalue  "), "plainvalue")
        XCTAssertEqual(CertificateRules.cleanPassword("https://site:8080"), "https://site:8080")
    }
}
