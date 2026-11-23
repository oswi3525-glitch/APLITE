import SwiftUI

/// Create or change APLite's own passcode. The input never leaves this view and is never logged.
struct PasscodeSetupView: View {
    @ObservedObject private var security = SecurityManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var newCode = ""
    @State private var confirm = ""
    @State private var message: String?
    @State private var success = false

    var body: some View {
        NavigationStack {
            Form {
                if security.isConfigured {
                    SecureField("Current passcode", text: $current)
                }
                SecureField("New passcode (at least 4 characters)", text: $newCode)
                SecureField("Confirm new passcode", text: $confirm)
                if let message {
                    Text(message).foregroundStyle(success ? APLiteColors.green : APLiteColors.red)
                }
                Section {
                    Button(saveTitle) { save() }
                        .disabled(newCode.isEmpty)
                        .buttonStyle(APLiteGlassButtonStyle())
                    if security.isConfigured {
                        Button("Remove passcode", role: .destructive) {
                            security.removePasscode()
                            message = String(localized: "APLite passcode removed.")
                            success = true
                        }
                    }
                }
            }
            .navigationTitle(security.isConfigured ? "Change passcode" : "Set passcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var saveTitle: String { security.isConfigured ? "Change passcode" : "Set passcode" }

    private func save() {
        do {
            if security.isConfigured {
                try security.changePasscode(current: current, to: newCode, confirm: confirm)
            } else {
                try security.setPasscode(newCode, confirm: confirm)
            }
            current = ""; newCode = ""; confirm = ""
            success = true
            message = String(localized: "APLite passcode saved in the Keychain.")
        } catch {
            success = false
            message = error.localizedDescription
        }
    }
}
