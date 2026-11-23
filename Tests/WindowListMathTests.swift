import XCTest

final class WindowListMathTests: XCTestCase {
    func testPanelFitsAboveTaskbarAndDoesNotGrowForever() {
        let screen = CGSize(width: 1920, height: 1080)
        let few = WindowListMath.panelRect(screen: screen, taskbarTop: 1032, count: 2)
        let many = WindowListMath.panelRect(screen: screen, taskbarTop: 1032, count: 99)
        XCTAssertLessThanOrEqual(few.maxY, 1032)
        XCTAssertLessThanOrEqual(many.maxY, 1032)
        XCTAssertGreaterThan(many.height, few.height)
        XCTAssertLessThanOrEqual(many.height,
                                 WindowListLayout.header + WindowListLayout.footer + 24
                                    + CGFloat(WindowListLayout.maxRows) * WindowListLayout.row)
    }

    func testRowCapNeverOverlapsTheFooter() {
        XCTAssertEqual(WindowListMath.visibleRows(count: 0), 0)
        XCTAssertEqual(WindowListMath.visibleRows(count: 4), 4)
        XCTAssertEqual(WindowListMath.visibleRows(count: 20), WindowListLayout.maxRows)
        let panel = WindowListMath.panelRect(screen: CGSize(width: 1280, height: 720),
                                            taskbarTop: 672, count: 20)
        let last = WindowListMath.rowRect(in: panel, index: WindowListMath.visibleRows(count: 20) - 1)
        XCTAssertLessThan(last.maxY, WindowListMath.footerRects(in: panel).tile.minY)
    }

    func testRowsCloseButtonAndFooterStayInsidePanel() {
        let panel = WindowListMath.panelRect(screen: CGSize(width: 1280, height: 720),
                                            taskbarTop: 672, count: 4)
        for i in 0..<4 {
            let row = WindowListMath.rowRect(in: panel, index: i)
            XCTAssertTrue(panel.contains(row))
            XCTAssertTrue(row.contains(WindowListMath.closeRect(in: row)))
        }
        let footer = WindowListMath.footerRects(in: panel)
        XCTAssertTrue(panel.contains(footer.tile))
        XCTAssertTrue(panel.contains(footer.desktop))
        XCTAssertLessThan(footer.tile.maxX, footer.desktop.minX)
    }
}
