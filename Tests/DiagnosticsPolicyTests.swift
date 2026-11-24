import XCTest

final class DiagnosticsPolicyTests: XCTestCase {
    func testFindingsPriority() {
        let list = DiagnosticsPolicy.findings(openWindows: 4, tabs: 8, backgroundTabs: 4,
                                              usedMB: 900, peakMB: 1000, targetMB: 1024,
                                              suspectedLeak: true, thermalWarm: true,
                                              audioInterrupted: true, audioErrors: 2,
                                              worstUIGap: 0.7, longGaps: 1,
                                              lastCrash: true, freeSpaceLow: true)
        XCTAssertEqual(list.first?.id, "crash")
        XCTAssertTrue(list.contains { $0.id == "lag" })
        XCTAssertTrue(list.contains { $0.id == "audio" })
        XCTAssertTrue(list.contains { $0.repair == .releaseCaches })
    }

    func testHealthyStateHasSingleInfoFinding() {
        let list = DiagnosticsPolicy.findings(openWindows: 1, tabs: 1, backgroundTabs: 0,
                                              usedMB: 200, peakMB: 250, targetMB: 1024,
                                              suspectedLeak: false, thermalWarm: false,
                                              audioInterrupted: false, audioErrors: 0,
                                              worstUIGap: 0.05, longGaps: 0,
                                              lastCrash: false, freeSpaceLow: false)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.severity, .info)
    }

    func testRedactionAndTruncation() {
        let text = "token=abc123 password: hunter2 cookie=session=xyz; ok"
        let redacted = DiagnosticsPolicy.redact(text)
        XCTAssertFalse(redacted.contains("hunter2"))
        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertTrue(redacted.contains("ok"))
        XCTAssertEqual(DiagnosticsPolicy.truncate(String(repeating: "x", count: 10), limit: 4).count, 5)
        XCTAssertEqual(DiagnosticsPolicy.truncate("abc", limit: 4), "abc")
    }

    func testRedactionCoversJSONBearerAndMoreKeys() {
        let text = """
        {"api_key": "sk-live-123", "private_key": "pem-secret", "client_secret": "cs-9"}
        Authorization: Bearer abc.def.ghi
        ?token=abc123&next=home
        pin: 1234 passcode=9999 session=sess-xyz
        """
        let redacted = DiagnosticsPolicy.redact(text)
        for secret in ["sk-live-123", "pem-secret", "cs-9", "abc.def.ghi", "abc123", "1234", "9999", "sess-xyz"] {
            XCTAssertFalse(redacted.contains(secret), "leaked \(secret) in \(redacted)")
        }
        XCTAssertTrue(redacted.contains("next=home"))
        XCTAssertTrue(redacted.contains("[redacted]"))
    }
}
