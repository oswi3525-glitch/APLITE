import SwiftUI

/// Privacy & Security tab. Groups access control, the user-visible system log, the account vault
/// and browser privacy. Existing controls keep their original keys and actions.
struct PrivacySettingsView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject private var security = SecurityManager.shared
    @AppStorage("APLite.security.lockOnLaunch") private var lockOnLaunch = false
    @AppStorage("APLite.security.lockOnSleep") private var lockOnSleep = true
    @AppStorage("APLite.security.authOnWake") private var authOnWake = true
    @State private var showPasscode = false

    var body: some View {
        List {
            Section("Access") {
                Button {
                    showPasscode = true
                } label: {
                    Label(security.isConfigured ? "Change APLite passcode" : "Set APLite passcode",
                          systemImage: "lock.shield")
                }
                Toggle("Lock when APLite opens", isOn: $lockOnLaunch)
                Toggle("Lock on sleep", isOn: $lockOnSleep)
                Toggle("Authenticate on wake", isOn: $authOnWake)
                if let deadline = security.lockoutUntil, deadline > Date() {
                    Text("Locked out until \(deadline.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(APLiteColors.orange)
                }
            }

            Section("Activity") {
                NavigationLink {
                    SystemLogView()
                } label: {
                    Label("System log", systemImage: "doc.text.magnifyingglass")
                }
                if APLite.isBeta {
                    NavigationLink {
                        SurveyExportView()
                    } label: {
                        Label("Export beta surveys", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section("Accounts") {
                Button("Save signed-in accounts") {
                    AccountCookies.shared.save { count in
                        model.showToast(String(localized: count > 0
                            ? "Saved \(count) login cookies."
                            : "No signed-in accounts were found on the desktop yet."))
                    }
                }
                Button("Save Google account only") {
                    GoogleSession.save { count in
                        model.showToast(String(localized: count > 0
                            ? "Saved \(count) Google cookies."
                            : "No Google account is signed in on the desktop yet."))
                    }
                }
                Text("Logins stay in APLite's local vault on this device only. Sensitive values are redacted before they reach the system log or an exported report.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Browser privacy") {
                Button { model.openPage(.browser) } label: {
                    Label("Browser settings", systemImage: "hand.raised")
                }
                Text("Content blockers work only inside web pages opened by APLite. iOS does not let an app scan or clean other apps.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Privacy & Security")
        .sheet(isPresented: $showPasscode) { PasscodeSetupView() }
    }
}
