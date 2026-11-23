import Foundation
import CoreGraphics

/// Pure geometry for the dock's compact window list. Shared by the view, the model's hit testing and
/// unit tests — no UIKit / SwiftUI here.
enum WindowListLayout {
    static let width: CGFloat = 360
    static let header: CGFloat = 50
    static let row: CGFloat = 46
    static let footer: CGFloat = 44
    static let padding: CGFloat = 12
    static let maxRows = 7
}

enum WindowListMath {
    /// Only this many windows are drawn and hit-tested; the rest stay reachable from Task Manager / Recents.
    static func visibleRows(count: Int) -> Int {
        min(WindowListLayout.maxRows, max(0, count))
    }

    static func panelRect(screen: CGSize, taskbarTop: CGFloat, count: Int) -> CGRect {
        let rows = max(1, visibleRows(count: count))
        let h = WindowListLayout.header + WindowListLayout.footer + WindowListLayout.padding * 2
            + CGFloat(rows) * WindowListLayout.row
        return CGRect(x: max(12, screen.width - WindowListLayout.width - 16),
                      y: max(12, taskbarTop - h - 10),
                      width: WindowListLayout.width, height: h)
    }

    static func rowRect(in panel: CGRect, index: Int) -> CGRect {
        CGRect(x: panel.minX + WindowListLayout.padding,
               y: panel.minY + WindowListLayout.header + CGFloat(index) * WindowListLayout.row,
               width: panel.width - WindowListLayout.padding * 2,
               height: WindowListLayout.row - 5)
    }

    static func closeRect(in row: CGRect) -> CGRect {
        CGRect(x: row.maxX - 34, y: row.minY + 8, width: 26, height: 26)
    }

    static func footerRects(in panel: CGRect) -> (tile: CGRect, desktop: CGRect) {
        let width = (WindowListLayout.width - WindowListLayout.padding * 2 - 12) / 2
        let tile = CGRect(x: panel.minX + WindowListLayout.padding,
                          y: panel.maxY - WindowListLayout.padding - 34,
                          width: width, height: 34)
        return (tile, CGRect(x: tile.maxX + 12, y: tile.minY, width: width, height: 34))
    }
}
