import Foundation

/// 8-bit sRGB components. Foundation-only so it can be unit tested without UIKit/SwiftUI.
struct RGB: Equatable {
    let r: UInt8
    let g: UInt8
    let b: UInt8

    var css: String { "rgb(\(r),\(g),\(b))" }
}

/// Strict #RRGGBB parsing used by the live accent manifest and for clamping color→CSS conversions.
enum HexColor {
    static func parse(_ raw: String) -> RGB? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        return RGB(r: UInt8((value >> 16) & 0xFF), g: UInt8((value >> 8) & 0xFF), b: UInt8(value & 0xFF))
    }

    /// A remote accent must not repaint the whole UI pink. Only cool/neutral values are accepted;
    /// APLite's own accent (#38BDF8) always passes.
    static func isPlausibleAccent(_ color: RGB) -> Bool {
        Int(color.b) >= Int(color.r) - 8
    }
}
