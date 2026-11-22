import XCTest

final class SecurityManagerTests: XCTestCase {
    func testBackoffEscalatesAndNeverShrinks() {
        XCTAssertEqual(SecurityManager.backoffSeconds(for: 0), 0)
        XCTAssertEqual(SecurityManager.backoffSeconds(for: 2), 0)
        XCTAssertEqual(SecurityManager.backoffSeconds(for: 3), 30)
        XCTAssertEqual(SecurityManager.backoffSeconds(for: 4), 30)
        XCTAssertEqual(SecurityManager.backoffSeconds(for: 5), 120)
        XCTAssertEqual(SecurityManager.backoffSeconds(for: 7), 120)
        XCTAssertEqual(SecurityManager.backoffSeconds(for: 8), 600)
        XCTAssertEqual(SecurityManager.backoffSeconds(for: 10), 3600)
        XCTAssertEqual(SecurityManager.backoffSeconds(for: 99), 3600)
        for n in 1...50 {
            XCTAssertGreaterThanOrEqual(SecurityManager.backoffSeconds(for: n + 1),
                                        SecurityManager.backoffSeconds(for: n))
        }
    }

    func testSettingsGroupsAreStable() {
        XCTAssertEqual(SettingsGroup.allCases.count, 10)
        XCTAssertEqual(SettingsGroup.security.rawValue, "security")
        XCTAssertEqual(SettingsGroup.certificates.rawValue, "certificates")
    }
}
