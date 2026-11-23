import SwiftUI

/// The desktop's on-screen keyboard. Drawn in SwiftUI on the external display, but every key is
/// hit-tested from a CGRect in DesktopModel — the display's scene receives no touches, so relying on
/// SwiftUI button taps would make the keys dead.
struct VirtualKeyboardView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var cursor: CursorModel

    var body: some View {
        let panel = model.virtualKeyboardRect
        let keys = KeyboardLayout.keyRects(in: panel, symbols: model.virtualKeyboardSymbols)

        ZStack(alignment: .topLeading) {
            HStack(spacing: 8) {
                Image(systemName: "keyboard").font(.system(size: 12, weight: .semibold))
                Text("Keyboard").font(.system(size: 12, weight: .semibold))
                if model.virtualKeyboardCaps || model.keyboardShiftActive || model.virtualKeyboardSymbols {
                    Text(modeLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                Spacer(minLength: 6)
                Text("Click a field to type · × hides")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(width: panel.width - KeyboardLayout.padding * 2, height: KeyboardLayout.header)
            .offset(x: KeyboardLayout.padding, y: 0)

            ForEach(keys.indices, id: \.self) { i in
                let item = keys[i]
                let hovered = item.rect.contains(cursor.position)
                let active = isActive(item.key)
                Text(verbatim: label(for: item.key))
                    .font(.system(size: fontSize(panel: panel), weight: .semibold, design: .monospaced))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .frame(width: item.rect.width, height: item.rect.height)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(active ? Color.accentColor.opacity(0.75)
                                 : hovered ? Color.white.opacity(0.22) : Color.white.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.white.opacity(active ? 0.55 : 0.14), lineWidth: 1)
                    )
                    .offset(x: item.rect.minX - panel.minX, y: item.rect.minY - panel.minY)
            }
        }
        .frame(width: panel.width, height: panel.height, alignment: .topLeading)
        .floatingPanel(cornerRadius: 16, shadow: 22)
        .offset(x: panel.minX, y: panel.minY)
        .allowsHitTesting(false)
    }

    private var modeLabel: String {
        if model.virtualKeyboardSymbols { return "Symbols" }
        if model.virtualKeyboardCaps { return model.virtualKeyboardShift ? "lower" : "Caps Lock" }
        return "Shift"
    }

    private func isActive(_ key: KeyboardLayout.Key) -> Bool {
        switch key.action {
        case .shift: return model.keyboardShiftActive
        case .capsLock: return model.virtualKeyboardCaps
        case .symbols: return model.virtualKeyboardSymbols
        default: return false
        }
    }

    private func label(for key: KeyboardLayout.Key) -> String {
        switch key.action {
        case .text:
            return model.keyboardShiftActive ? (key.shifted ?? key.label.uppercased()) : key.label
        case .hide:
            return "×"
        default:
            return key.label
        }
    }

    private func fontSize(panel: CGRect) -> CGFloat {
        min(19, max(11, KeyboardLayout.unitWidth(for: panel.width) * 0.42))
    }
}
