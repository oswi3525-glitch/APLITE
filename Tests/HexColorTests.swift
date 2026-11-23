import XCTest

final class HexColorTests: XCTestCase {
    func testStrictParsing() {
        XCTAssertEqual(HexColor.parse("#FF0000"), RGB(r: 255, g: 0, b: 0))
        XCTAssertEqual(HexColor.parse(" 00ffcc "), RGB(r: 0, g: 255, b: 204))
        XCTAssertEqual(HexColor.parse("38BDF8"), RGB(r: 0x38, g: 0xBD, b: 0xF8))
        XCTAssertNil(HexColor.parse("#fff"))
        XCTAssertNil(HexColor.parse("not-a-color"))
        XCTAssertNil(HexColor.parse("#GG0000"))
    }

    func testRemoteAccentCannotTurnTheUIPink() {
        XCTAssertFalse(HexColor.isPlausibleAccent(HexColor.parse("#FF8080")!))
        XCTAssertFalse(HexColor.isPlausibleAccent(HexColor.parse("#FF0000")!))
        XCTAssertTrue(HexColor.isPlausibleAccent(HexColor.parse("#38BDF8")!))
        XCTAssertTrue(HexColor.isPlausibleAccent(HexColor.parse("#8E8E93")!))
    }

    func testCSSOutput() {
        XCTAssertEqual(HexColor.parse("#FF0000")?.css, "rgb(255,0,0)")
    }
}
