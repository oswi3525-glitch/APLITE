import XCTest

final class KeyboardLayoutTests: XCTestCase {
    func testEveryRowFitsFifteenUnits() {
        for rows in [KeyboardLayout.letterRows, KeyboardLayout.symbolRows] {
            for row in rows {
                let units = row.reduce(0.0) { $0 + $1.units }
                XCTAssertLessThanOrEqual(units, KeyboardLayout.columns, "row too wide: \(row.map(\.label))")
            }
        }
    }

    func testPanelSitsAboveTaskbarAndInsideScreen() {
        let screen = CGSize(width: 1920, height: 1080)
        let rect = KeyboardLayout.panelRect(screen: screen, taskbarTop: 1032)
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertLessThanOrEqual(rect.maxX, screen.width)
        XCTAssertLessThanOrEqual(rect.maxY, 1032)
        XCTAssertGreaterThan(rect.height, 200)
    }

    func testKeysAreHitTestableAndInsidePanel() {
        let screen = CGSize(width: 1280, height: 720)
        let panel = KeyboardLayout.panelRect(screen: screen, taskbarTop: 672)
        let keys = KeyboardLayout.keyRects(in: panel, symbols: false)
        XCTAssertFalse(keys.isEmpty)
        for item in keys {
            XCTAssertTrue(panel.contains(item.rect), "\(item.key.label) escaped the panel")
            XCTAssertEqual(KeyboardLayout.key(at: CGPoint(x: item.rect.midX, y: item.rect.midY),
                                              in: panel, symbols: false), item.key)
        }
    }

    func testShiftLayerHasUppercaseAndSymbols() {
        XCTAssertTrue(KeyboardLayout.letterRows.flatMap { $0 }.contains { $0.label == "q" && $0.shifted == "Q" })
        XCTAssertTrue(KeyboardLayout.letterRows.flatMap { $0 }.contains { $0.label == "1" && $0.shifted == "!" })
        XCTAssertTrue(KeyboardLayout.symbolRows.flatMap { $0 }.contains { $0.action == .symbols })
        XCTAssertTrue(KeyboardLayout.letterRows.flatMap { $0 }.contains { $0.action == .hide })
    }
}
