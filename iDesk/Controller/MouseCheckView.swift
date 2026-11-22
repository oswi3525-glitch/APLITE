import SwiftUI

/// What iOS actually delivers from a mouse, through each path, live: tells whether this iPhone hands the mouse to
/// iDesk directly (GameController) or only through AssistiveTouch. Opened from the mouse status on the iPhone.
struct MouseCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var assistiveTouch = UIAccessibility.isAssistiveTouchRunning

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let c = MouseInput.shared.counters
                List {
                    Section {
                        Text("Move the mouse, press each button and turn the wheel. With AssistiveTouch on, also move its pointer over the trackpad area of the iPhone.")
                            .font(.callout)
                    }
                    Section {
                        Label(verdict(c), systemImage: c.moves > 0 ? "checkmark.circle.fill" : "info.circle")
                            .foregroundStyle(c.moves > 0 ? Color.green : Color.primary)
                    }
                    Section {
                        row("Mice iOS reports", c.miceFound)
                        row("Connect events", c.connects)
                        if c.withoutInput > 0 { row("Connected without mouse input", c.withoutInput) }
                        row("Movements", c.moves)
                        row("Left button", c.buttons)
                        row("Right button", c.rightButtons)
                        row("Middle button", c.middleButtons)
                        row("Wheel", c.scrolls)
                        if !c.lastMouseName.isEmpty { LabeledContent("Mouse", value: c.lastMouseName) }
                    } header: {
                        Text("Direct (GameController)")
                    } footer: {
                        Text("Movements here mean the mouse works without AssistiveTouch.")
                    }
                    Section {
                        LabeledContent("AssistiveTouch", value: assistiveTouch ? String(localized: "On") : String(localized: "Off"))
                        row("Pointer movements", c.pointerHover)
                        row("Clicks", c.pointerPresses)
                        row("Right clicks", c.pointerRightPresses)
                        row("Wheel", c.pointerScrolls)
                    } header: {
                        Text("Through AssistiveTouch")
                    } footer: {
                        Text("AssistiveTouch can give the right and middle buttons to its own menu: Settings → Accessibility → Touch → AssistiveTouch → Devices lets you change what they do.")
                    }
                }
            }
            .navigationTitle("Mouse check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.assistiveTouchStatusDidChangeNotification)) { _ in
                assistiveTouch = UIAccessibility.isAssistiveTouchRunning
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ title: LocalizedStringKey, _ value: Int) -> some View {
        LabeledContent(title) { Text(verbatim: "\(value)").monospacedDigit() }
    }

    private func verdict(_ c: MouseInput.Counters) -> String {
        if c.moves > 0 {
            return String(localized: "The mouse works directly. AssistiveTouch is not needed.")
        }
        if c.pointerHover > 0 || c.pointerPresses > 0 {
            return String(localized: "The mouse only reaches iDesk through AssistiveTouch. Use mouse mode (the corner button on the trackpad) to point straight at the desktop.")
        }
        if c.miceFound > 0 || c.connects > 0 {
            return String(localized: "iOS reports a mouse but sends iDesk no movement. Turn on AssistiveTouch to use it through its pointer.")
        }
        return String(localized: "iOS reports no mouse to iDesk. On iPhone a mouse is turned on by AssistiveTouch: Settings → Accessibility → Touch → AssistiveTouch, then connect the mouse.")
    }
}
