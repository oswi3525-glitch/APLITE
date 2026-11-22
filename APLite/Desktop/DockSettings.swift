import SwiftUI

/// How the floating dock looks. Stored in UserDefaults and mirrored by DesktopModel's
/// @Published properties, so changing a slider redraws the desktop immediately.
enum DockAppearance: Int, CaseIterable {
    case dark = 0
    case light = 1
    case automatic = 2
}

enum DockSettings {
    static let scaleKey = "APLite.dock.scale"
    static let iconScaleKey = "APLite.dock.iconScale"
    static let spacingKey = "APLite.dock.spacing"
    static let opacityKey = "APLite.dock.opacity"
    static let magnificationKey = "APLite.dock.magnification"
    static let appearanceKey = "APLite.dock.appearance"

    static let scaleRange: ClosedRange<Double> = 0.85...1.25
    static let iconScaleRange: ClosedRange<Double> = 0.8...1.2
    static let spacingRange: ClosedRange<Double> = 4...16
    static let opacityRange: ClosedRange<Double> = 0.5...1

    static let defaultScale = 1.0
    static let defaultIconScale = 1.0
    static let defaultSpacing = 8.0
    static let defaultOpacity = 0.82
    static let defaultMagnification = true
    static let defaultAppearance = DockAppearance.dark

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    static func double(_ key: String, default value: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? value
    }
}

/// Colours for the dock's glass, icons and labels. The desktop itself stays dark (as the original
/// app's windows do); this lets the dock follow a light or dark look without changing guest apps.
struct DockPalette {
    let fill: Color
    let stroke: Color
    let primary: Color
    let secondary: Color
    let hover: Color
    let active: Color

    init(mode: Int, scheme: ColorScheme) {
        let appearance = DockAppearance(rawValue: mode) ?? .dark
        let light: Bool
        switch appearance {
        case .dark: light = false
        case .light: light = true
        case .automatic: light = scheme == .light
        }
        if light {
            fill = Color.white.opacity(0.62)
            stroke = Color.black.opacity(0.10)
            primary = Color.black.opacity(0.88)
            secondary = Color.black.opacity(0.55)
            hover = Color.black.opacity(0.08)
            active = Color.accentColor
        } else {
            fill = Color.black.opacity(0.34)
            stroke = Color.white.opacity(0.14)
            primary = Color.white.opacity(0.95)
            secondary = Color.white.opacity(0.62)
            hover = Color.white.opacity(0.14)
            active = Color.accentColor
        }
    }
}
