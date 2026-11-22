import CoreGraphics
import Foundation

/// A plain snapshot of a window's state (no UIKit objects), used for save/restore and unit tests.
struct WindowSnapshot: Equatable {
    let id: UUID
    let frame: CGRect
    let minimized: Bool
    let maximized: Bool
    let keepOnTop: Bool
}

/// Pure window maths, shared by the coordinator and the unit tests.
enum WindowLayout {
    /// A balanced grid of frames for `count` windows inside `area`. Deterministic and testable.
    static func grid(count: Int, in area: CGRect, gap: CGFloat = 12) -> [CGRect] {
        guard count > 0, area.width > 0, area.height > 0 else { return [] }
        let columns = max(1, Int(ceil(sqrt(Double(count)))))
        let rows = max(1, Int(ceil(Double(count) / Double(columns))))
        let width = max(80, (area.width - gap * CGFloat(columns - 1)) / CGFloat(columns))
        let height = max(60, (area.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
        return (0..<count).map { index in
            let column = index % columns, row = index / columns
            return CGRect(x: area.minX + CGFloat(column) * (width + gap),
                          y: area.minY + CGFloat(row) * (height + gap),
                          width: width, height: height)
        }
    }

    /// Keeps a restored window at least partly on screen (a display may have changed resolution).
    static func clamp(_ frame: CGRect, to area: CGRect) -> CGRect {
        guard area.width > 0, area.height > 0 else { return frame }
        var result = frame
        result.size.width = min(max(frame.width, 240), area.width)
        result.size.height = min(max(frame.height, 160), area.height)
        result.origin.x = min(max(frame.minX, area.minX), max(area.minX, area.maxX - result.width))
        result.origin.y = min(max(frame.minY, area.minY), max(area.minY, area.maxY - result.height))
        return result
    }
}
