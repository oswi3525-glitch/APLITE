import XCTest
import Security

final class P12ImportErrorMapperTests: XCTestCase {
    func testAuthFailureIsNotReportedAsUnsupportedFormat() {
        XCTAssertEqual(P12ImportErrorMapper.reason(for: errSecAuthFailed), .wrongPasswordOrDamaged)
    }

    func testModernEncryptionStatusesAreNotCalledWrongPassword() {
        XCTAssertEqual(P12ImportErrorMapper.reason(for: errSecParam), .unsupportedEncryptionOrDamaged)
        XCTAssertEqual(P12ImportErrorMapper.reason(for: errSecDecode), .unsupportedEncryptionOrDamaged)
    }

    func testUnknownStatusKeepsItsCode() {
        XCTAssertEqual(P12ImportErrorMapper.reason(for: -99999), .other(-99999))
    }

    func testMessagesDoNotBlindlyBlameTheFile() {
        let message = P12ImportErrorMapper.message(for: .unsupportedEncryptionOrDamaged)
        XCTAssertTrue(message.contains("openssl"))
        XCTAssertFalse(message.contains("password is wrong"))
    }
}
