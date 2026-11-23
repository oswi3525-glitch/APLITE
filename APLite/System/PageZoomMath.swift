import Foundation

/// Pure zoom-level math shared by the keyboard shortcuts, window menus and the Settings page.
/// Foundation-only so it can be unit tested in the standalone test target.
enum PageZoomMath {
    static let levels: [Double] = [0.5, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]
    static let `default`: Double = 1.0
    static let epsilon = 0.01

    static func percent(_ zoom: Double) -> Int { Int((zoom * 100).rounded()) }

    static func isValid(_ zoom: Double) -> Bool { levels.contains { abs($0 - zoom) < epsilon } }

    static func nearest(_ zoom: Double) -> Double {
        levels.min { abs($0 - zoom) < abs($1 - zoom) } ?? `default`
    }

    /// step 0 means Reset (always back to 100%); ±1 moves one level and clamps at the ends.
    static func stepped(from zoom: Double, by step: Int) -> Double {
        guard step != 0 else { return `default` }
        let current = nearest(zoom)
        guard let index = levels.firstIndex(of: current) else { return `default` }
        let next = index + (step > 0 ? 1 : -1)
        return levels[min(max(0, next), levels.count - 1)]
    }
}
