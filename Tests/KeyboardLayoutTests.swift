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

    func testHeaderControlsAreInsideStripAndHitTested() {
        let panel = KeyboardLayout.panelRect(screen: CGSize(width: 1280, height: 720), taskbarTop: 672)
        let buttons = KeyboardLayout.headerButtons(in: panel)
        XCTAssertTrue(KeyboardLayout.headerRect(in: panel).contains(buttons.primary))
        XCTAssertTrue(KeyboardLayout.headerRect(in: panel).contains(buttons.close))
        XCTAssertLessThan(buttons.primary.maxX, buttons.close.minX)
        XCTAssertEqual(KeyboardLayout.headerTarget(at: CGPoint(x: buttons.close.midX, y: buttons.close.midY),
                                                   in: panel, minimized: false), .close)
        XCTAssertEqual(KeyboardLayout.headerTarget(at: CGPoint(x: buttons.primary.midX, y: buttons.primary.midY),
                                                   in: panel, minimized: false), .minimize)
        XCTAssertEqual(KeyboardLayout.headerTarget(at: CGPoint(x: buttons.primary.midX, y: buttons.primary.midY),
                                                   in: panel, minimized: true), .expand)
        XCTAssertEqual(KeyboardLayout.headerTarget(at: CGPoint(x: panel.minX + 60, y: panel.minY + 10),
                                                   in: panel, minimized: false), .drag)
        XCTAssertEqual(KeyboardLayout.headerTarget(at: CGPoint(x: panel.midX, y: panel.midY),
                                                   in: panel, minimized: false), .none)
    }

    func testLargestScaleStillFitsOnASmallDisplay() {
        let screen = CGSize(width: 1280, height: 720)
        let rect = KeyboardLayout.panelRect(screen: screen, taskbarTop: 672, scale: 1.4)
        XCTAssertLessThanOrEqual(rect.minX, 8)
        XCTAssertLessThanOrEqual(rect.maxX, screen.width - 8)
        for item in KeyboardLayout.keyRects(in: rect, symbols: false) {
            XCTAssertLessThanOrEqual(item.rect.maxX, screen.width - 8, "\(item.key.label) is off screen")
        }
    }

    func testDraggedAndMinimizedPanelsStayOnScreen() {
        let screen = CGSize(width: 1280, height: 720)
        let taskbarTop: CGFloat = 672
        let base = KeyboardLayout.panelRect(screen: screen, taskbarTop: taskbarTop)
        let far = KeyboardLayout.panelRect(at: CGPoint(x: 9000, y: -500), screen: screen,
                                           taskbarTop: taskbarTop, scale: 1)
        XCTAssertLessThanOrEqual(far.minX, screen.width - base.width)
        XCTAssertGreaterThanOrEqual(far.minY, 0)
        XCTAssertLessThanOrEqual(far.maxY, taskbarTop)

        let strip = KeyboardLayout.minimizedRect(from: far)
        XCTAssertEqual(strip.origin, far.origin)
        XCTAssertLessThanOrEqual(strip.maxY, taskbarTop)
        XCTAssertLessThanOrEqual(strip.width, base.width)
    }
}
