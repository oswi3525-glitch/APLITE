import SwiftUI

/// The desktop's on-screen keyboard. Drawn in SwiftUI on the external display, but every control is
/// hit-tested from a CGRect in DesktopModel — the display's scene receives no touches, so relying on
/// SwiftUI button taps would make the keys (and the new title-strip controls) dead.
struct VirtualKeyboardView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var cursor: CursorModel

    var body: some View {
        let panel = model.virtualKeyboardRect
        if model.virtualKeyboardMinimized {
            collapsedBody(panel: panel)
        } else {
            expandedBody(panel: panel)
        }
    }

    // MARK: Expanded

    private func expandedBody(panel: CGRect) -> some View {
        let base = model.virtualKeyboardBaseRect
        let keys = KeyboardLayout.keyRects(in: base, symbols: model.virtualKeyboardSymbols)
        let buttons = KeyboardLayout.headerButtons(in: panel)
        return ZStack(alignment: .topLeading) {
            titleBar(panel: panel, minimized: false)
            ForEach(keys.indices, id: \.self) { i in
                keyView(keys[i], panel: base)
            }
            control(symbol: "minus", rect: buttons.primary, panel: panel)
            control(symbol: "xmark", rect: buttons.close, panel: panel)
        }
        .frame(width: panel.width, height: panel.height, alignment: .topLeading)
        .floatingPanel(cornerRadius: 16, shadow: 22)
        .offset(x: panel.minX, y: panel.minY)
        .allowsHitTesting(false)
    }

    private func keyView(_ item: (key: KeyboardLayout.Key, rect: CGRect), panel: CGRect) -> some View {
        let hovered = item.rect.contains(cursor.position)
        let pressed = hovered && cursor.isPressed
        let active = isActive(item.key)
        let fill = LinearGradient(
            colors: active ? [Color.accentColor.opacity(0.92), Color.accentColor.opacity(0.62)]
                    : pressed ? [Color.white.opacity(0.38), Color.white.opacity(0.20)]
                    : hovered ? [Color.white.opacity(0.28), Color.white.opacity(0.16)]
                    : [Color.white.opacity(0.13), Color.white.opacity(0.07)],
            startPoint: .top, endPoint: .bottom)
        return Text(verbatim: label(for: item.key))
            .font(.system(size: fontSize(panel: panel), weight: .semibold, design: .monospaced)) // taste:allow monospace — keycap labels
            .minimumScaleFactor(0.55)
            .lineLimit(1)
            .frame(width: item.rect.width, height: item.rect.height)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(active ? 0.55 : hovered ? 0.32 : 0.13),
                            lineWidth: hovered ? 1.4 : 0.8)
            )
            .offset(x: item.rect.minX - panel.minX, y: item.rect.minY - panel.minY)
    }

    // MARK: Collapsed strip

    private func collapsedBody(panel: CGRect) -> some View {
        let buttons = KeyboardLayout.headerButtons(in: panel)
        return ZStack(alignment: .topLeading) {
            titleBar(panel: panel, minimized: true)
            control(symbol: "plus", rect: buttons.primary, panel: panel)
            control(symbol: "xmark", rect: buttons.close, panel: panel)
        }
        .frame(width: panel.width, height: panel.height, alignment: .topLeading)
        .floatingPanel(cornerRadius: 14, shadow: 18)
        .offset(x: panel.minX, y: panel.minY)
        .allowsHitTesting(false)
    }

    // MARK: Shared pieces

    private func titleBar(panel: CGRect, minimized: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Color.accentColor.opacity(0.95),
                                                  Color.accentColor.opacity(0.50)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 20, height: 20)
            Text("Keyboard")
                .font(.system(size: 12.5, weight: .semibold))
            if !minimized && (model.virtualKeyboardCaps || model.keyboardShiftActive
                              || model.virtualKeyboardSymbols) {
                Text(modeLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer(minLength: 6)
            Text(minimized ? "Collapsed · + to expand" : "Drag the title bar · × hides")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.trailing, 52)     // room for the two controls drawn over the strip
        .frame(width: panel.width - KeyboardLayout.padding * 2, height: KeyboardLayout.header)
        .offset(x: KeyboardLayout.padding, y: 0)
    }

    private func control(symbol: String, rect: CGRect, panel: CGRect) -> some View {
        let hovered = rect.contains(cursor.position)
        return Image(systemName: symbol)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(hovered ? Color.white : Color.white.opacity(0.78))
            .frame(width: rect.width, height: rect.height)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovered ? Color.accentColor.opacity(0.92) : Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(hovered ? 0.5 : 0.16), lineWidth: 0.8)
            )
            .offset(x: rect.minX - panel.minX, y: rect.minY - panel.minY)
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
