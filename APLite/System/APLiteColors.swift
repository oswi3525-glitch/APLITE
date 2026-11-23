import SwiftUI
import UIKit

/// One source of truth for APLite's signal colors. Values are pinned to calibrated sRGB through
/// UIColor, so SwiftUI's forced dark color scheme, dynamic system colors and P3 device color space
/// cannot shift a declared red into pink. The blue matches the asset catalog and desktop CSS #38BDF8.
enum APLiteColors {
    static let accent = Color(uiColor: UIColor(red: 0x38 / 255, green: 0xBD / 255, blue: 0xF8 / 255, alpha: 1))

    /// A declared #FF0000 stays exactly pure red, in light glass and in dark mode.
    static let redUI = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    static let red = Color(uiColor: redUI)
    /// Opaque dark red for translucent badges over light glass: alpha compositing white over pure
    /// red makes pink, so pre-darken the red instead of lowering its alpha.
    static let redOnGlass = Color(uiColor: UIColor(red: 0.62, green: 0, blue: 0, alpha: 1))
    static let orange = Color(uiColor: UIColor(red: 1, green: 0.58, blue: 0, alpha: 1))
    static let green = Color(uiColor: UIColor(red: 0.18, green: 0.82, blue: 0.36, alpha: 1))
}
