import SwiftUI

/// Apps tab. Only reuses existing app-management actions; nothing here claims APLite can install
/// an arbitrary IPA on iOS (code signing and sandbox forbid that).
struct AppsSettingsView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject private var guest = GuestStore.shared
    @ObservedObject private var webApps = WebApps.shared

    var body: some View {
        List {
            Section("Installed apps") {
                Button { model.openPage(.apps) } label: {
                    Label("Manage iOS apps", systemImage: "square.grid.2x2")
                }
                LabeledContent("Web apps", value: "\(webApps.all.count)")
                LabeledContent("Native modules", value: "\(guest.apps.count)")
                Toggle("Reopen guest apps at launch", isOn: $model.reopenApps)
            }

            Section("Web shortcuts") {
                Button("Add Zalo, Facebook, Telegram, Chrome, YouTube, Gmail") {
                    let added = BuiltInWebApps.installMissing()
                    model.showToast(String(localized: added > 0
                        ? "Added \(added) web apps to the desktop."
                        : "Those web apps are already installed."))
                }
                Text("Web shortcuts open in APLite's browser. Native versions need a signed IPA and a signing app; iOS does not allow an app to install arbitrary IPAs.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Native modules") {
                if guest.apps.isEmpty {
                    Text("No native modules are bundled with this build.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(guest.apps) { app in
                        LabeledContent(app.name, value: app.status.text)
                    }
                }
                Button("Open the Apps page") { model.openPage(.apps) }
            }
        }
        .navigationTitle("Apps")
    }
}
