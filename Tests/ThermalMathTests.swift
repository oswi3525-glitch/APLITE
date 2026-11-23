import XCTest

final class ThermalMathTests: XCTestCase {
    func testPublicStateBandsAreOrderedAndClamped() {
        let targets = [0, 1, 2, 3].map { ThermalMath.targetPressure(rawState: $0) }
        XCTAssertEqual(targets.count, 4)
        for i in 1..<targets.count { XCTAssertLessThan(targets[i - 1], targets[i]) }
        XCTAssertEqual(ThermalMath.targetPressure(rawState: -1), 0.5)
        XCTAssertEqual(ThermalMath.targetPressure(rawState: 99), 0.5)
    }

    func testSmoothingMovesTowardsTargetAndNeverLeavesZeroToOne() {
        XCTAssertEqual(ThermalMath.smooth(current: 0.2, target: 0.2), 0.2, accuracy: 0.0001)
        XCTAssertGreaterThan(ThermalMath.smooth(current: 0.1, target: 0.9), 0.1)
        XCTAssertLessThan(ThermalMath.smooth(current: 0.1, target: 0.9), 0.9)
        XCTAssertEqual(ThermalMath.smooth(current: 0.8, target: 9), 1)
        XCTAssertEqual(ThermalMath.smooth(current: 0.2, target: -9), 0)
    }

    func testTrendUsesADeadband() {
        XCTAssertEqual(ThermalMath.trend(from: 0.30, to: 0.50), .rising)
        XCTAssertEqual(ThermalMath.trend(from: 0.50, to: 0.30), .falling)
        XCTAssertEqual(ThermalMath.trend(from: 0.50, to: 0.51), .steady)
    }

    func testPercentAndDurationFormatting() {
        XCTAssertEqual(ThermalMath.percent(-1), 0)
        XCTAssertEqual(ThermalMath.percent(0.456), 46)
        XCTAssertEqual(ThermalMath.percent(2), 100)
        XCTAssertEqual(ThermalMath.duration(45), "45s")
        XCTAssertEqual(ThermalMath.duration(125), "2m 5s")
        XCTAssertEqual(ThermalMath.duration(3720), "1h 2m")
    }
}
