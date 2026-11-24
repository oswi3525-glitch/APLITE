import SwiftUI

/// APStore: browses the apps that are genuinely inside APLite's distribution — web shortcuts and
/// signed native modules. It cannot install arbitrary IPAs: iOS signing rules and the sandbox do
/// not let a third-party app do that. Native modules still require the existing signed export flow.
struct APStoreView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject private var guest = GuestStore.shared
    @ObservedObject private var webApps = WebApps.shared

    private var webListings: [APStoreCatalog.Listing] {
        APStoreCatalog.webListings { url in webApps.isInstalled(url) }
    }
    private var nativeListings: [APStoreCatalog.Listing] {
        APStoreCatalog.nativeListings(from: guest.apps)
    }

    var body: some View {
        List {
            Section("Web Apps") {
                ForEach(webListings) { listing in
                    HStack(spacing: APLiteDesign.Space.md) {
                        Image(systemName: "globe")
                            .foregroundStyle(APLiteColors.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: APLiteDesign.Space.xs) {
                            Text(listing.title).font(APLiteDesign.Typography.body)
                            Text(listing.detail).font(APLiteDesign.Typography.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if listing.installed {
                            Text("Installed").font(APLiteDesign.Typography.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Get") { install(listing) }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, APLiteDesign.Space.xs)
                }
            }

            Section("Native Modules") {
                if nativeListings.isEmpty {
                    Text("This build has no bundled native modules.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(nativeListings) { listing in
                        VStack(alignment: .leading, spacing: APLiteDesign.Space.xs) {
                            Label(listing.title, systemImage: "shippingbox")
                            Text(listing.detail).font(APLiteDesign.Typography.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Manage modules in Apps") { model.openPage(.apps) }
                Button("Show module hashes") { verifyIntegrity() }
            }

            Section("About APStore") {
                Text("Web Apps are website shortcuts that open in APLite's browser. Native Modules are code bundled and signed together with APLite; they need an official signed build. APLite cannot install arbitrary IPA files from outside — iOS signature and sandbox rules forbid it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("APStore")
    }

    private func install(_ listing: APStoreCatalog.Listing) {
        guard listing.kind == .webApp,
              let app = BuiltInWebApp.allCases.first(where: { $0.title == listing.title }),
              let url = URL(string: app.url) else { return }
        let icon: UIImage? = app.iconName.flatMap(UIImage.init(named:)) ?? UIImage(systemName: app.symbol)
        webApps.install(url, title: app.title, icon: icon)
        APLog.info("APStore installed web app: \(app.title)", module: "APStore")
        model.showToast(String(localized: "Added \(app.title) to the desktop."))
    }

    private func verifyIntegrity() {
        var checked = 0
        for app in guest.apps {
            let plist = app.bundleURL.appendingPathComponent("Info.plist")
            if let hash = APStoreIntegrity.sha256Hex(ofFile: plist) {
                checked += 1
                APLog.info("Integrity hash for \(app.name): \(hash)", module: "APStore")
            } else {
                APLog.error("Cannot read integrity hash for \(app.name)", module: "APStore")
            }
        }
        model.showToast(String(localized: "Recorded \(checked) module hash(es) in the system log. Compare with the official build manifest."))
    }
}
