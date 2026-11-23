import XCTest

final class PageZoomMathTests: XCTestCase {
    func testRequestedLevels() {
        XCTAssertEqual(PageZoomMath.levels, [0.5, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0])
        XCTAssertTrue(PageZoomMath.levels == PageZoomMath.levels.sorted())
    }

    func testSteppingClampsAndReset() {
        XCTAssertEqual(PageZoomMath.stepped(from: 1.0, by: 1), 1.1)
        XCTAssertEqual(PageZoomMath.stepped(from: 1.0, by: -1), 0.9)
        XCTAssertEqual(PageZoomMath.stepped(from: 0.5, by: -1), 0.5)
        XCTAssertEqual(PageZoomMath.stepped(from: 2.0, by: 1), 2.0)
        XCTAssertEqual(PageZoomMath.stepped(from: 1.75, by: 0), 1.0)
    }

    func testNearestAndPercent() {
        XCTAssertEqual(PageZoomMath.nearest(1.3), 1.25)
        XCTAssertEqual(PageZoomMath.nearest(0.6), 0.5)
        XCTAssertEqual(PageZoomMath.percent(1.25), 125)
        XCTAssertTrue(PageZoomMath.isValid(1.1))
        XCTAssertFalse(PageZoomMath.isValid(1.3))
    }
}
