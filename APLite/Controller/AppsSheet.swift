import SwiftUI
import UniformTypeIdentifiers

/// Manages apps installed from IPA files: import, open, remove, and the certificate used for re-signing.
struct AppsSheet: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject private var store = GuestStore.shared
    @ObservedObject private var signing = SigningStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var pending: CertificateFiles?     // have a .p12 but not the right password yet
    @State private var password = ""
    @State private var message: String?
    @State private var exportProgress: Double?          // exporting the package for the signing app
    @State private var showAdvanced = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.apps.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No apps yet. Tap “Add IPA” to add one.")
                            Text("The IPA file must be decrypted: copies from the App Store can't run. After adding it, tap “Install new apps into APLite” and pick ESign. Apps installed from the App Store can't open on the desktop; use their website instead.")
                                .font(.footnote)
                        }
                        .foregroundStyle(.secondary)
                    }
                    ForEach(store.apps) { app in
                        Button { open(app) } label: { row(app) }
                            .swipeActions {
                                if !app.isBundled || app.hasPendingUpdate {
                                    Button("Delete", role: .destructive) { store.remove(app) }
                                } else {
                                    // The app is bundled inside APLite: it can only be removed by reinstalling APLite.
                                    Button(app.pendingRemoval ? "Keep" : "Remove from APLite",
                                           role: app.pendingRemoval ? nil : .destructive) { store.toggleRemoval(app) }
                                }
                            }
                    }
                    Button {
                        DocumentPicker.present(completion: handlePicked)
                    } label: {
                        if let p = store.installProgress, p.total > 1 {
                            Label("Adding \(p.done + 1) of \(p.total)…", systemImage: "plus.app")
                        } else {
                            Label(store.isInstalling ? "Adding…" : "Add IPA", systemImage: "plus.app")
                        }
                    }
                    .disabled(store.isInstalling || exportProgress != nil)
                } header: {
                    HStack {
                        Text("Apps")
                        Spacer()
                        if store.totalSize > 0 { Text(Self.format(store.totalSize)) }
                    }
                } footer: {
                    Text("Decrypted IPAs only. Swipe left to delete an app or remove it from APLite to save space. Several apps can run at once; each one uses memory, so iOS may close APLite if too many are open.")
                }

                #if !targetEnvironment(simulator)
                if store.hasPendingExport || exportProgress != nil {
                    Section {
                        if let progress = exportProgress {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Preparing the install file…")
                                ProgressView(value: progress)
                            }
                            .padding(.vertical, 4)
                        } else {
                            Button(action: export) {
                                Label(store.apps.contains(where: \.pendingRemoval) && !store.apps.contains(where: { !$0.isBundled || $0.hasPendingUpdate })
                                      ? "Reinstall APLite (remove selected apps)" : "Install new apps into APLite",
                                      systemImage: "square.and.arrow.down.on.square")
                                    .font(.headline)
                            }
                        }
                    } header: {
                        Text("Install into APLite")
                    } footer: {
                        Text("iOS only runs code that is inside an installed app, so new apps must be installed into APLite once: tap the button above, pick ESign (or Feather, Scarlet… whichever signing app you use), then sign and install as usual. Reopen APLite and the app runs.")
                    }
                }

                Section {
                    DisclosureGroup("Advanced: sign on this device", isExpanded: $showAdvanced) {
                        certificateStatus
                        Button {
                            DocumentPicker.present(completion: handlePicked)
                        } label: {
                            Label(signing.identity == nil ? "Import certificate" : "Change certificate", systemImage: "key")
                        }
                        if signing.identity != nil {
                            Button("Delete certificate", role: .destructive) { signing.removeCertificate() }
                        }
                    }
                } footer: {
                    if showAdvanced {
                        Text("Only works when APLite is installed with a development certificate (get-task-allow, e.g. through SideStore/AltStore). With a regular ESign certificate iOS blocks this; use “Install new apps into APLite” instead.")
                    }
                }
                #endif
            }
            .navigationTitle("Apps from IPA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Password for the .p12 file", isPresented: Binding(get: { pending != nil },
                                                                  set: { if !$0 { pending = nil } })) {
                SecureField("Password", text: $password)
                Button("Cancel", role: .cancel) { password = "" }
                Button("Import") { importCertificate() }
            }
            .alert("APLite", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                let text = message ?? ""
                Button("Copy") { UIPasteboard.general.string = text }
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ app: GuestApp) -> some View {
        HStack(spacing: 12) {
            Group {
                if let icon = app.icon {
                    Image(uiImage: icon).resizable()
                } else {
                    Image(systemName: "app.fill").resizable().foregroundStyle(.teal)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).foregroundStyle(.primary)
                status(app)
            }
            Spacer()
            Image(systemName: "play.fill").foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
    }

    private func status(_ app: GuestApp) -> some View {
        let s = app.status
        let color: Color = switch s.tone { case .good: .green; case .warn: .orange; case .bad: .red; case .muted: .secondary }
        return Text(verbatim: s.text).font(.caption).foregroundStyle(color)
    }

    static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    @ViewBuilder private var certificateStatus: some View {
        if let identity = signing.identity {
            VStack(alignment: .leading, spacing: 4) {
                Text(identity.commonName)
                Text("Team ID: \(identity.teamID)").font(.caption).foregroundStyle(.secondary)
                if signing.matchesOwnTeam == false {
                    Label("Different Team ID from APLite (\(signing.ownTeamID ?? "?")): iOS will refuse to load the app.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if identity.chain.isEmpty {
                    Label("The Apple WWDR intermediate certificate is missing (not in the .p12 file nor in APLite’s signature). iOS may reject the signature.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("APLite is signed by Team: \(signing.ownTeamID ?? String(localized: "unreadable"))")
                    .font(.caption).foregroundStyle(.secondary)
                debugEntitlementStatus
                profileStatus
            }
        } else {
            #if targetEnvironment(simulator)
            Text("The Simulator needs no certificate.").foregroundStyle(.secondary)
            #else
            Label("No certificate yet: guest apps cannot run.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            #endif
        }
    }

    /// iOS only lets guest apps load from outside the bundle with get-task-allow (see GuestStore.canLoadOutsideBundle).
    @ViewBuilder private var debugEntitlementStatus: some View {
        #if !targetEnvironment(simulator)
        Text(OwnSignature.getTaskAllow == true
             ? "APLite has get-task-allow (development certificate)."
             : "APLite lacks get-task-allow: iOS may reject apps signed on this device; install them into APLite through ESign instead.")
            .font(.caption).foregroundStyle(.secondary)
        #endif
    }

    @ViewBuilder private var profileStatus: some View {
        if let profile = signing.profile {
            Text("Profile: \(profile.name)").font(.caption).foregroundStyle(.secondary)
            if let date = profile.expiration {
                Text("Expires: \(date.formatted(date: .numeric, time: .omitted))")
                    .font(.caption).foregroundStyle(profile.isExpired ? .red : .secondary)
            }
            if signing.profileMatchesCertificate == false {
                Label("The profile does not match this certificate.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        } else {
            Text("No .mobileprovision file (optional).").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func open(_ app: GuestApp) {
        guard model.isExternalConnected else {
            message = String(localized: "Connect an external display first; the app opens as a window on the desktop.")
            return
        }
        dismiss()
        model.openApp(app)
    }

    private func export() {
        exportProgress = 0
        store.exportForESign(progress: { value in
            DispatchQueue.main.async { if exportProgress != nil { exportProgress = value } }
        }, completion: { result in
            exportProgress = nil
            switch result {
            case .success(let file): ShareSheet.present(file)
            case .failure(let error): message = String(localized: "Could not create the file: \(error.localizedDescription)")
            }
        })
    }

    private func install(_ urls: [URL]) {
        store.install(ipas: urls) { results in
            let added = results.filter { (try? $0.result.get()) != nil }.count
            #if targetEnvironment(simulator)
            message = GuestStore.summary(of: results)
            #else
            if GuestStore.canLoadOutsideBundle {
                message = GuestStore.summary(of: results, next: String(localized: "Tap an app to open it on the desktop."))
            } else if added == results.count {
                // Go straight to installing: package everything once, then open the share sheet for the signing app.
                export()
            } else {
                // Some failed: say which (the "Install new apps into APLite" button packages the ones that worked).
                message = GuestStore.summary(of: results)
            }
            #endif
        }
    }

    /// The user picked one or more files: IPA, .zip, .p12, .mobileprovision, pass.txt.
    private func handlePicked(_ urls: [URL]) {
        let files = CertificateFiles.collect(urls)
        if files.isEmpty {
            let names = files.unknown.isEmpty ? "" : " (\(files.unknown.joined(separator: ", ")))"
            message = String(localized: "Unrecognized file\(names). Choose an .ipa file, a certificate .zip, or cert.p12 / .mobileprovision / pass.txt.")
            return
        }
        if !files.ipas.isEmpty { install(files.ipas) }
        if files.p12 != nil {
            if let unlocked = try? files.unlock() {
                save(files, unlocked)
            } else {
                // No pass.txt, or the password in it is wrong: ask the user.
                password = ""
                pending = files
            }
        } else if let profile = files.profile {
            do {
                try signing.importProfile(profile)
                message = summary(prefix: String(localized: "Imported the .mobileprovision file."))
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func importCertificate() {
        guard let files = pending else { return }
        pending = nil
        defer { password = "" }
        do {
            save(files, try files.unlock(typed: password))
        } catch {
            message = error.localizedDescription
        }
    }

    private func save(_ files: CertificateFiles, _ unlocked: (identity: CodeSigner.Identity, password: String)) {
        do {
            if let p12 = files.p12 { try signing.importCertificate(p12: p12, password: unlocked.password) }
            if let profile = files.profile { try signing.importProfile(profile) }
            try store.resignAll()
            message = summary(prefix: store.apps.isEmpty ? String(localized: "Certificate imported.") : String(localized: "Certificate imported and installed apps re-signed."))
        } catch {
            message = error.localizedDescription
        }
    }

    /// Certificate + profile summary, with a warning if something does not match.
    private func summary(prefix: String) -> String {
        var lines = [prefix]
        if let identity = signing.identity { lines.append("\(identity.commonName)\nTeam ID: \(identity.teamID)") }
        if let profile = signing.profile {
            var line = String(localized: "Profile: \(profile.name)")
            if let date = profile.expiration { line += String(localized: ", expires \(date.formatted(date: .numeric, time: .omitted))") }
            lines.append(line)
            if profile.isExpired { lines.append(String(localized: "⚠️ The profile has expired.")) }
        }
        if signing.profileMatchesCertificate == false {
            lines.append(String(localized: "⚠️ The .mobileprovision file does not match this certificate."))
        }
        if signing.matchesOwnTeam == false {
            lines.append(String(localized: "⚠️ The Team ID differs from the certificate signing APLite (\(signing.ownTeamID ?? "?")); iOS will refuse to load apps. Sign APLite in ESign with this same certificate."))
        }
        return lines.joined(separator: "\n\n")
    }
}
