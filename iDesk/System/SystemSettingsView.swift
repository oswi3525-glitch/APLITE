import SwiftUI
import UniformTypeIdentifiers

/// The grouped, desktop-style settings surface for the independent APLite modules. It is native
/// SwiftUI on the iPhone so every control is real and persists through APLiteSettings / the
/// existing model — nothing here is decorative.
struct SystemSettingsView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject private var security = SecurityManager.shared
    @ObservedObject private var power = PowerManager.shared
    @ObservedObject private var memory = MemoryManager.shared
    @ObservedObject private var certificates = CertificateManager.shared

    @AppStorage("APLite.security.lockOnLaunch") private var lockOnLaunch = false
    @AppStorage("APLite.security.lockOnSleep") private var lockOnSleep = true
    @AppStorage("APLite.security.authOnWake") private var authOnWake = true
    @AppStorage("APLite.security.autoLock") private var autoLock = 15
    @AppStorage("APLite.power.restoreSession") private var restoreSession = true
    @AppStorage("APLite.power.suspendWork") private var suspendWork = true
    @AppStorage("APLite.performance.memoryTargetMB") private var memoryTarget = 1024
    @AppStorage("APLite.performance.warnPercent") private var warnPercent = 80
    @AppStorage("APLite.performance.releaseCaches") private var releaseCaches = true
    @AppStorage("APLite.performance.detectLeaks") private var detectLeaks = true
    @AppStorage("APLite.personalization.pressRipples") private var pressRipples = false

    @State private var showPasscode = false
    @State private var showBuildCenter = false
    @State private var showCertificatePassword = false
    @State private var certificatePassword = ""
    @State private var pendingCertificate: Data?
    @State private var resolution = ""

    private var apliteUsage: (files: Int, bytes: UInt64) { APLiteFileManager.systemUsage() }
    private var brightnessText: String { "\(Int((model.externalBrightness * 100).rounded()))%" }

    var body: some View {
        List {
            Section(SettingsGroup.personalization.title) {
                Toggle("Reduce motion", isOn: $model.reduceMotion)
                Toggle("Performance mode", isOn: $model.performanceMode)
                Toggle("Clock and calendar widgets", isOn: $model.showWidgets)
                Toggle("Circular press effect", isOn: $pressRipples)
            }

            Section(SettingsGroup.security.title) {
                Toggle("Lock when APLite opens", isOn: $lockOnLaunch)
                Toggle("Lock on sleep", isOn: $lockOnSleep)
                Toggle("Authenticate on wake", isOn: $authOnWake)
                Picker("Auto-lock after", selection: $autoLock) {
                    ForEach(APLiteSettings.Security.autoLockOptions, id: \.self) { Text(minuteLabel($0)) }
                }
                Button { showPasscode = true } label: {
                    Label(security.isConfigured ? "Change APLite passcode" : "Set APLite passcode",
                          systemImage: "lock.shield")
                }
                if let deadline = security.lockoutUntil, deadline > Date() {
                    Text("Locked out until \(deadline.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.orange)
                }
            }

            Section(SettingsGroup.power.title) {
                LabeledContent("State", value: power.state.label)
                Button("Sleep") { power.sleep() }
                Button("Wake") { power.wake() }
                .disabled(power.state != .sleeping)
                Button("Shut down APLite", role: .destructive) { power.shutdown() }
                Button("Restart APLite") { power.boot() }
                .disabled(power.state != .shutDown)
                Toggle("Suspend guest apps on sleep", isOn: $suspendWork)
                Toggle("Restore the last session", isOn: $restoreSession)
                Text("These control the APLite environment only. iOS does not allow an app to switch the iPhone or iPad off or on.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section(SettingsGroup.performance.title) {
                Picker("Memory target", selection: $memoryTarget) {
                    ForEach(APLiteSettings.Performance.memoryTargets, id: \.self) { Text("\($0) MB") }
                }
                Picker("Warn at", selection: $warnPercent) {
                    ForEach([60, 70, 80, 90], id: \.self) { Text("\($0)%") }
                }
                Toggle("Release caches when idle", isOn: $releaseCaches)
                Toggle("Detect possible memory leaks", isOn: $detectLeaks)
                Text(memory.report()).font(.footnote).foregroundStyle(.secondary)
                Button("Release caches now") { memory.releaseCaches(reason: "user request") }
            }

            Section(SettingsGroup.applications.title) {
                Button { model.openPage(.apps) } label: {
                    Label("Manage iOS apps", systemImage: "square.grid.2x2")
                }
                Button("Add Chrome, Zalo, Facebook, Telegram") {
                    let n = BuiltInWebApps.installMissing()
                    model.showToast(String(localized: n > 0
                        ? "Added \(n) web apps to the desktop."
                        : "Those web apps are already installed."))
                }
                Text("Web shortcuts. Native versions need a decrypted IPA added in Apps.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Reopen guest apps at launch", isOn: $model.reopenApps)
            }

            Section("Accounts") {
                Button("Save signed-in Google account") {
                    GoogleSession.save { count in
                        model.showToast(String(localized: count > 0
                            ? "Saved \(count) Google cookies."
                            : "No Google account is signed in on the desktop yet."))
                    }
                }
                Text("Stored locally in APLite's cookie vault. Never sent anywhere.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section(SettingsGroup.storage.title) {
                LabeledContent("APLite managed files", value: "\(apliteUsage.files) files · \(APLiteFileManager.sizeText(Int64(apliteUsage.bytes)))")
                Button("Save a diagnostics report") {
                    if APLiteFileManager.writeDiagnostics() != nil {
                        model.showToast(String(localized: "Diagnostics saved in APLite's file area."))
                    }
                }
                Button("Open Files") { model.openPage(.files) }
            }

            Section(SettingsGroup.display.title) {
                Picker("Resolution", selection: $resolution) {
                    Text("Automatic").tag("")
                    ForEach(ExternalDisplay.resolutions.map(ExternalDisplay.name(of:)), id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: resolution) { _, value in
                    let parts = value.split(separator: "x").compactMap { Double($0) }
                    ExternalDisplay.resolution = parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
                }
                LabeledContent("Brightness", value: brightnessText)
                Button("TV mode (720p, larger text)") {
                    DesktopPages.handle(.settings, action: "tvMode", value: "")
                }
            }

            Section(SettingsGroup.input.title) {
                Toggle("Natural scrolling", isOn: InputSettings.naturalScrollingBinding)
            }

            Section(SettingsGroup.certificates.title) {
                LabeledContent("Certificate", value: certificates.identityName ?? String(localized: "None"))
                if let error = certificates.lastError { Text(error).foregroundStyle(.red).font(.footnote) }
                Button("Import .p12 / .pfx from Files") { importCertificate() }
                if certificates.hasIdentity {
                    Button("Remove certificate", role: .destructive) { certificates.remove() }
                }
            }

            Section(SettingsGroup.system.title) {
                NavigationLink { SystemChangelogView() } label: { Label("What's new", systemImage: "sparkles") }
                LabeledContent("Version", value: APLite.displayVersion)
                LabeledContent("Last clean shutdown", value: APLiteSettings.System.lastShutdown?.formatted() ?? String(localized: "never"))
                Button("Build Center") { showBuildCenter = true }
                NavigationLink { AboutView() } label: { Label("Attribution", systemImage: "info.circle") }
            }
        }
        .navigationTitle("System settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { resolution = ExternalDisplay.resolution.map(ExternalDisplay.name(of:)) ?? "" }
        .sheet(isPresented: $showPasscode) { PasscodeSetupView() }
        .sheet(isPresented: $showBuildCenter) { BuildCenterView() }
        .alert("Certificate password", isPresented: $showCertificatePassword) {
            SecureField("Password", text: $certificatePassword)
            Button("Cancel", role: .cancel) { pendingCertificate = nil }
            Button("Import") {
                guard let data = pendingCertificate else { return }
                do {
                    try certificates.import(p12: data, password: certificatePassword)
                    model.showToast(String(localized: "Certificate imported."))
                } catch {
                    model.showToast(error.localizedDescription)
                }
                pendingCertificate = nil
                certificatePassword = ""
            }
        } message: {
            Text("Enter the password for the .p12 / .pfx file. It is stored in the Keychain and never logged.")
        }
    }

    private func minuteLabel(_ minutes: Int) -> String {
        minutes == 0 ? String(localized: "Never") : "\(minutes) min"
    }

    private func importCertificate() {
        DocumentPicker.present { urls in
            guard let url = urls.first else { return }
            do {
                pendingCertificate = try CertificateManager.shared.readCertificate(from: url)
                certificatePassword = ""
                showCertificatePassword = true
            } catch {
                model.showToast(error.localizedDescription)
            }
        }
    }
}

extension InputSettings {
    /// Binding for the native settings list (the value is read from UserDefaults on every use).
    static var naturalScrollingBinding: Binding<Bool> {
        Binding(get: { naturalScrolling }, set: { naturalScrolling = $0 })
    }
}
