import SwiftUI

// MARK: - Dynamic wallpaper

/// Wallpaper index -2: colours that follow the time of day (dawn, day, sunset, night), changing every few minutes.
enum DynamicWallpaper {
    static let index = -2

    static func colors(at date: Date) -> [Color] {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
        // Key times and their three colours; between two keys the colours blend.
        let keys: [(Double, [(Double, Double, Double)])] = [
            (0, [(0.02, 0.03, 0.10), (0.06, 0.05, 0.18), (0.01, 0.08, 0.14)]),
            (5.5, [(0.10, 0.08, 0.25), (0.35, 0.18, 0.40), (0.05, 0.10, 0.25)]),
            (7, [(0.95, 0.55, 0.40), (0.55, 0.40, 0.65), (0.20, 0.30, 0.55)]),
            (10, [(0.30, 0.60, 0.90), (0.45, 0.70, 0.95), (0.15, 0.40, 0.70)]),
            (16, [(0.25, 0.55, 0.85), (0.50, 0.65, 0.90), (0.15, 0.35, 0.65)]),
            (18.5, [(0.95, 0.45, 0.25), (0.70, 0.25, 0.40), (0.25, 0.12, 0.35)]),
            (20, [(0.12, 0.10, 0.30), (0.25, 0.12, 0.35), (0.04, 0.08, 0.20)]),
            (24, [(0.02, 0.03, 0.10), (0.06, 0.05, 0.18), (0.01, 0.08, 0.14)]),
        ]
        var i = 0
        while i < keys.count - 2, h >= keys[i + 1].0 { i += 1 }
        let (t0, a) = keys[i], (t1, b) = keys[i + 1]
        let k = max(0, min(1, (h - t0) / max(0.01, t1 - t0)))
        return (0..<3).map { j in
            Color(red: a[j].0 + (b[j].0 - a[j].0) * k, green: a[j].1 + (b[j].1 - a[j].1) * k, blue: a[j].2 + (b[j].2 - a[j].2) * k)
        }
    }

    /// For the Settings page swatch.
    static func cssColors(at date: Date) -> [String] {
        colors(at: date).map { c in
            let u = UIColor(c); var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            u.getRed(&r, green: &g, blue: &b, alpha: &a)
            return String(format: "rgb(%d,%d,%d)", Int(r * 255), Int(g * 255), Int(b * 255))
        }
    }
}

// MARK: - Night filter

/// Settings → Display → Night filter: warmer colours on the display (less blue light), always or from 21:00 to 7:00.
enum NightFilter {
    enum Mode: Int { case off, schedule, always }
    private static let key = "iDesk.nightFilter"
    static var mode: Mode {
        get { Mode(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .off }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key); DesktopModel.shared.objectWillChange.send() }
    }

    static func isActive(at date: Date) -> Bool {
        switch mode {
        case .off: return false
        case .always: return true
        case .schedule:
            let h = Calendar.current.component(.hour, from: date)
            return h >= 21 || h < 7
        }
    }
}

struct NightFilterView: View {
    /// Passed in so the view redraws when the setting changes.
    let mode: NightFilter.Mode

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            if mode != .off && NightFilter.isActive(at: ctx.date) {
                Color(red: 1.0, green: 0.62, blue: 0.25).opacity(0.28)
                    .blendMode(.multiply)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Shake to find the pointer

/// Moving the pointer quickly back and forth makes it big for a moment, to find it on a large screen (as on a Mac).
final class ShakeDetector {
    private var lastDX: CGFloat = 0
    private var turns: [CFTimeInterval] = []
    private var travel: CGFloat = 0

    /// Returns true when the movements so far make a shake.
    func feed(dx: CGFloat) -> Bool {
        let now = CACurrentMediaTime()
        guard abs(dx) > 2 else { return false }
        travel += abs(dx)
        if lastDX != 0, (dx > 0) != (lastDX > 0) {
            turns.append(now)
            turns.removeAll { now - $0 > 0.9 }
            if turns.count >= 4, travel > 500 {
                turns = []
                travel = 0
                lastDX = dx
                return true
            }
        }
        if turns.isEmpty || now - (turns.last ?? now) > 0.9 { travel = abs(dx) }
        lastDX = dx
        return false
    }
}
