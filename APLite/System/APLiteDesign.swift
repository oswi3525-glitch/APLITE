import SwiftUI

/// One set of native design tokens for APLite surfaces.
///
/// These translate the "one system" rule into SwiftUI: a single value for each spacing step,
/// corner radius, type role and surface colour, so the boot screen, panels and settings cannot
/// drift into separate visual languages. Values are chosen to match the existing glass/button
/// treatment (`APLiteGlassButtonStyle`) so adopting a token never changes how a view looks.
enum APLiteDesign {
    enum Space {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 28
    }

    enum Radius {
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 22
    }

    enum Typography {
        static let display = Font.system(size: 28, weight: .semibold, design: .rounded)
        static let title = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let body = Font.subheadline
        static let caption = Font.footnote
    }

    enum Surface {
        /// Deep, flat boot ground. No image, no large blur: cheap on iPhone and iPad.
        static let bootBackground = SwiftUI.Color(red: 0.025, green: 0.04, blue: 0.065)
        static let bootGlow = APLiteColors.accent
        static let primaryText = SwiftUI.Color.white
        static let secondaryText = SwiftUI.Color.white.opacity(0.62)
        static let statusText = SwiftUI.Color.white.opacity(0.76)
    }

    static let touchTarget: CGFloat = 44
    static let bootMarkSize: CGFloat = 76
    static let bootContentMaxWidth: CGFloat = 480
    static let bootStatusMaxWidth: CGFloat = 360
}
