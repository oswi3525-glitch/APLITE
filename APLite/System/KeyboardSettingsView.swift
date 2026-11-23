import SwiftUI

/// The full on-screen-keyboard settings page on the iPhone. Every key the desktop keyboard supports
/// is shown here so it is discoverable, and every option is a real persisted APLite setting.
struct KeyboardSettingsView: View {
    @ObservedObject var model: DesktopModel
    @AppStorage("APLite.input.virtualKeyboard") private var enabled = false
    @AppStorage("APLite.input.keyboardAlwaysVisible") private var alwaysVisible = false
    @AppStorage("APLite.input.keyboardSize") private var size = 100
    @AppStorage("APLite.input.keyboardFeedback") private var feedback = true

    var body: some View {
        List {
            Section {
                Toggle("Show keyboard on the desktop", isOn: $enabled)
                Toggle("Keep it visible when no field is focused", isOn: $alwaysVisible)
                    .disabled(!enabled)
                Picker("Key size", selection: $size) {
                    ForEach(APLiteSettings.Input.keyboardSizes, id: \.self) { Text("\($0)%").tag($0) }
                }
                Toggle("Click feedback on iPhone", isOn: $feedback)
                Text("The keyboard appears on the external display only when you click an input field (or another text field such as the address bar). Use the × key or Esc to put it away; the next field you click brings it back. Shift changes case for one key, Caps Lock keeps it, and 123 switches to the symbol layer.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("On-screen keyboard")
            }

            Section {
                keyMap(title: "Letters", rows: KeyboardLayout.letterRows)
                keyMap(title: "Symbols (123)", rows: KeyboardLayout.symbolRows)
            } header: {
                Text("All keys")
            } footer: {
                Text("Keys are sent to the focused field: web pages, APLite's own apps, guest apps, the find bar and the address bar all work.")
            }
        }
        .navigationTitle("On-screen keyboard")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func keyMap(title: String, rows: [[KeyboardLayout.Key]]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                            Text(verbatim: key.label)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                                .frame(width: max(26, 18 * CGFloat(key.units)), height: 26)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.10)))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.14), lineWidth: 1))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
