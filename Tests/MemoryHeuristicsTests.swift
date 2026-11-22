import XCTest

final class MemoryHeuristicsTests: XCTestCase {
    private let mb: UInt64 = 1024 * 1024

    func testNeedsEnoughSamples() {
        XCTAssertFalse(MemoryHeuristics.looksLikeLeak((1...7).map { UInt64($0) * 10 * 1024 * 1024 }))
    }

    func testSteadyGrowthIsSuspicious() {
        let values = (0..<8).map { UInt64(300 + $0 * 10) * 1024 * 1024 }
        XCTAssertTrue(MemoryHeuristics.looksLikeLeak(values))
    }

    func testGrowthBelowThresholdIsIgnored() {
        let values = (0..<8).map { UInt64(300 + $0) * 1024 * 1024 }
        XCTAssertFalse(MemoryHeuristics.looksLikeLeak(values))
    }

    func testDroppingSamplesAreNotALeak() {
        let values = (0..<8).map { UInt64(300 + ($0 % 2) * 100) * 1024 * 1024 }
        XCTAssertFalse(MemoryHeuristics.looksLikeLeak(values))
    }
}
