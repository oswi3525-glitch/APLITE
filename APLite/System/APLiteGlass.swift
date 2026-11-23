import SwiftUI

/// One glass button treatment for APLite's own screens (Settings, Build Center, passcode).
/// Unlike SwiftUI's default styles it has no circular press halo; feedback is a gentle tint and
/// a very small scale that becomes instant under Reduce Motion.
struct APLiteGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(isEnabled ? (configuration.isPressed ? 0.20 : 0.10) : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.14), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed && !APLiteAnimation.reduced ? 0.98 : 1)
            .animation(APLiteAnimation.snappy, value: configuration.isPressed)
            .opacity(isEnabled ? 1 : 0.5)
    }
}
