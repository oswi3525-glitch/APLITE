import XCTest

final class APLogPolicyTests: XCTestCase {
    func testRotationThreshold() {
        XCTAssertFalse(APLogRotation.shouldRotate(currentSize: 100, incomingBytes: 10))
        XCTAssertFalse(APLogRotation.shouldRotate(currentSize: APLogRotation.maxBytes - 1, incomingBytes: 1))
        XCTAssertTrue(APLogRotation.shouldRotate(currentSize: APLogRotation.maxBytes, incomingBytes: 1))
    }

    func testRotationFileSetIsBounded() {
        let urls = APLogRotation.urls(in: URL(fileURLWithPath: "/tmp/logs"))
        XCTAssertEqual(urls.count, APLogRotation.maxRotations + 1)
        XCTAssertEqual(urls.first?.lastPathComponent, "aplite-system.log")
        XCTAssertEqual(urls.last?.lastPathComponent, "aplite-system.2.log")
    }

    func testLevelsAndRedaction() {
        XCTAssertEqual(APLogLevel.allCases.map(\.rawValue), ["debug", "info", "error", "fault"])
        let raw = "cookie=session=xyz token=abc ok"
        XCTAssertFalse(DiagnosticsPolicy.redact(raw).contains("abc"))
        XCTAssertTrue(DiagnosticsPolicy.redact(raw).contains("ok"))
    }
}
