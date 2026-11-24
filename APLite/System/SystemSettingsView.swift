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

    @AppStorage("APLite.security.lockOnLaunch") private var lockOnLaunch = false
    @AppStorage("APLite.security.lockOnSleep") private var lockOnSleep = true
    @AppStorage("APLite.security.authOnWake") private var authOnWake = true
    @AppStorage("APLite.security.autoLock") private var autoLock = 15
    @AppStorage("APLite.power.restoreSession") private var restoreSession = true
    @AppStorage("APLite.power.suspendWork") private var suspendWork = true
    @AppStorage("APLite.performance.memoryTargetMB") private var memoryTarget = 1024
    @AppStorage("APLite.performance.warnPercent") private var warnPercent = 80
    @AppStorage("APLite.performance.detectLeaks") private var detectLeaks = true
    @AppStorage("APLite.personalization.pressRipples") private var pressRipples = false
    @AppStorage("APLite.input.virtualKeyboard") private var virtualKeyboard = false
    @AppStorage("APLite.personalization.settingsAppearance") private var settingsAppearance = 0

    @State private var showPasscode = false
    @State private var resolution = ""
    @State private var pendingAction: (() -> Void)?
    @State private var confirmMessage = ""
    @State private var confirmLabel = "Confirm"

    private var apliteUsage: (files: Int, bytes: UInt64) { APLiteFileManager.systemUsage() }
    private var brightnessText: String { "\(Int((model.externalBrightness * 100).rounded()))%" }

    var body: some View {
        List {
            Section(header: Label(SettingsGroup.personalization.title, systemImage: SettingsGroup.personalization.symbol)) {
                Picker("Settings appearance", selection: $settingsAppearance) {
                    Text("Follow system").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                Toggle("Reduce motion", isOn: $model.reduceMotion)
                Toggle("Performance mode", isOn: $model.performanceMode)
                Toggle("Clock and calendar widgets", isOn: $model.showWidgets)
                Toggle("Circular press effect", isOn: $pressRipples)
            }

            Section(header: Label("Wallpaper", systemImage: "photo")) {
                Picker("Style", selection: $model.wallpaper) {
                    ForEach(Wallpapers.photos, id: \.index) { photo in
                        Text(photo.name == "MeadowWallpaper" ? "Đồng cỏ (meadow)" : "Biển (ocean)")
                            .tag(photo.index)
                    }
                    Text("Dynamic").tag(DynamicWallpaper.index)
                    Text("Your photo").tag(-1)
                    ForEach(0..<Wallpapers.count, id: \.self) { i in
                        Text("Gradient \(i + 1)").tag(i)
                    }
                }
                Slider(value: $model.wallpaperBlur, in: 0...20, step: 1) {
                    Text("Blur")
                }
                Text("Choose a photo from Photos or Files in the desktop Settings → Wallpaper.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section(header: Label(SettingsGroup.security.title, systemImage: SettingsGroup.security.symbol)) {
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

            Section(header: Label(SettingsGroup.power.title, systemImage: SettingsGroup.power.symbol)) {
                LabeledContent("State", value: power.state.label)
                Button("Sleep") { power.sleep() }
                Button("Wake") { power.wake() }
                .disabled(power.state != .sleeping)
                Button("Shut down APLite", role: .destructive) {
                    confirmMessage = "All open pages and guest apps will close. This is a soft shutdown of APLite only."
                    confirmLabel = "Shut down APLite"
                    pendingAction = { power.shutdown() }
                }
                Button("Restart APLite") { power.boot() }
                .disabled(power.state != .shutDown)
                Toggle("Suspend guest apps on sleep", isOn: $suspendWork)
                Toggle("Restore the last session", isOn: $restoreSession)
                Text("These control the APLite environment only. iOS does not allow an app to switch the iPhone or iPad off or on.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section(header: Label(SettingsGroup.performance.title, systemImage: SettingsGroup.performance.symbol)) {
                Picker("Memory target", selection: $memoryTarget) {
                    ForEach(APLiteSettings.Performance.memoryTargets, id: \.self) { Text("\($0) MB") }
                }
                Picker("Warn at", selection: $warnPercent) {
                    ForEach([60, 70, 80, 90], id: \.self) { Text("\($0)%") }
                }
                Toggle("Detect possible memory leaks", isOn: $detectLeaks)
                Text(memory.report()).font(.footnote).foregroundStyle(.secondary)
                Button("Release caches now") {
                    confirmMessage = "Web and image caches are cleared; pages may reload once."
                    confirmLabel = "Release caches now"
                    pendingAction = { memory.releaseCaches(reason: "user request") }
                }
            }

            Section(header: Label(SettingsGroup.applications.title, systemImage: SettingsGroup.applications.symbol)) {
                Button { model.openPage(.apps) } label: {
                    Label("Manage iOS apps", systemImage: "square.grid.2x2")
                }
                Button("Add Zalo, Facebook, Telegram, Chrome, YouTube, Gmail") {
                    let n = BuiltInWebApps.installMissing()
                    model.showToast(String(localized: n > 0
                        ? "Added \(n) web apps to the desktop."
                        : "Those web apps are already installed."))
                }
                Text("Web shortcuts. Native versions need a decrypted IPA added in Apps.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Reopen guest apps at launch", isOn: $model.reopenApps)
            }

            Section(header: Label("Accounts", systemImage: "person.crop.circle")) {
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
                Text("Logins in any web window — including those on the external display — are copied to APLite's local vault automatically. Stored on this device only; never sent anywhere.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section(header: Label(SettingsGroup.storage.title, systemImage: SettingsGroup.storage.symbol)) {
                LabeledContent("APLite managed files", value: "\(apliteUsage.files) files · \(APLiteFileManager.sizeText(Int64(apliteUsage.bytes)))")
                Button("Save a diagnostics report") {
                    if APLiteFileManager.writeDiagnostics() != nil {
                        model.showToast(String(localized: "Diagnostics saved in APLite's file area."))
                    }
                }
                Button("Open Files") { model.openPage(.files) }
            }

            Section(header: Label(SettingsGroup.display.title, systemImage: SettingsGroup.display.symbol)) {
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

            Section(header: Label(SettingsGroup.input.title, systemImage: SettingsGroup.input.symbol)) {
                Toggle("Natural scrolling", isOn: InputSettings.naturalScrollingBinding)
                Toggle("On-screen keyboard", isOn: $virtualKeyboard)
                NavigationLink {
                    KeyboardSettingsView(model: model)
                } label: {
                    Label("Keyboard settings & all keys", systemImage: "keyboard")
                }
                Text("The desktop keyboard appears when you click a field. Drag it by its title bar, collapse or close it with the corner controls. See the page above for every key.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section(header: Label(SettingsGroup.system.title, systemImage: SettingsGroup.system.symbol)) {
                NavigationLink { AdvancedSettingsView(model: model) } label: {
                    Label("Advanced tools", systemImage: "wrench.and.screwdriver")
                }
                NavigationLink { SystemChangelogView() } label: { Label("What's new", systemImage: "sparkles") }
                LabeledContent("Version", value: APLite.displayVersion)
                LabeledContent("Last clean shutdown", value: APLiteSettings.System.lastShutdown?.formatted() ?? String(localized: "never"))
                NavigationLink { AboutView() } label: { Label("Attribution", systemImage: "info.circle") }
            }
        }
        .navigationTitle("System settings")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .preferredColorScheme(settingsScheme)
        .onAppear { resolution = ExternalDisplay.resolution.map(ExternalDisplay.name(of:)) ?? "" }
        .sheet(isPresented: $showPasscode) { PasscodeSetupView() }
        .alert("Confirm action", isPresented: Binding(get: { pendingAction != nil },
                                                     set: { if !$0 { pendingAction = nil } })) {
            Button("Cancel", role: .cancel) { pendingAction = nil }
            Button(confirmLabel, role: .destructive) { pendingAction?(); pendingAction = nil }
        } message: {
            Text(confirmMessage)
        }
    }

    private var settingsScheme: ColorScheme? {
        switch APLiteSettings.SettingsAppearance(rawValue: settingsAppearance) ?? .system {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    private func minuteLabel(_ minutes: Int) -> String {
        minutes == 0 ? String(localized: "Never") : "\(minutes) min"
    }

}

extension InputSettings {
    /// Binding for the native settings list (the value is read from UserDefaults on every use).
    static var naturalScrollingBinding: Binding<Bool> {
        Binding(get: { naturalScrolling }, set: { naturalScrolling = $0 })
    }
}
