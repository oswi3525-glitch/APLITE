import XCTest

final class CleanupPolicyTests: XCTestCase {
    func testCachesAndTemporaryPrefixes() {
        let caches = URL(fileURLWithPath: "/var/mobile/Containers/Data/Application/X/Library/Caches/TikTok/video.mp4")
        XCTAssertEqual(CleanupPolicy.category(for: caches), .caches)

        let export = URL(fileURLWithPath: "/tmp/export-12345.plist")
        XCTAssertEqual(CleanupPolicy.category(for: export), .temporaryFiles)

        let unrelated = URL(fileURLWithPath: "/tmp/keep-me.txt")
        XCTAssertNil(CleanupPolicy.category(for: unrelated))
    }

    func testOnlyAPLiteAreaIsClassified() {
        let liveLog = URL(fileURLWithPath: "/Library/Application Support/APLite/Logs/aplite-system.log")
        XCTAssertEqual(CleanupPolicy.category(for: liveLog), .oldLogs)

        let report = URL(fileURLWithPath: "/Library/Application Support/APLite/diagnostics-20260101-000000.txt")
        XCTAssertEqual(CleanupPolicy.category(for: report), .oldDiagnostics)

        let foreign = URL(fileURLWithPath: "/Library/Application Support/OtherApp/diagnostics-old.txt")
        XCTAssertNil(CleanupPolicy.category(for: foreign))
    }

    func testAgeRule() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(CleanupPolicy.isExpired(now.addingTimeInterval(-60), days: 7, now: now))
        XCTAssertTrue(CleanupPolicy.isExpired(now.addingTimeInterval(-8 * 86_400), days: 7, now: now))
        XCTAssertTrue(CleanupPolicy.isExpired(nil, days: 7, now: now))
    }
}
