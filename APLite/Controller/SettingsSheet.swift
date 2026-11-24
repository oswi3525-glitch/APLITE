import SwiftUI

/// Pointer / scroll speed, stored in UserDefaults (read by the trackpad on every use).
enum InputSettings {
    static let pointerKey = "iDesk.pointerSpeed"
    static let scrollKey = "iDesk.scrollSpeed"
    static let naturalScrollingKey = "iDesk.naturalScrolling"
    static let defaultPointer = 1.6
    static let defaultScroll = 3.4

    static var pointerSpeed: CGFloat {
        CGFloat(UserDefaults.standard.object(forKey: pointerKey) as? Double ?? defaultPointer)
    }
    static var scrollSpeed: CGFloat {
        CGFloat(UserDefaults.standard.object(forKey: scrollKey) as? Double ?? defaultScroll)
    }

    /// Natural scrolling (as on a Mac or iPhone: the content follows the fingers / the wheel), or traditional
    /// (traditional: the other way round). For the trackpad, the mouse wheel and AssistiveTouch's wheel.
    static var naturalScrolling: Bool {
        get { UserDefaults.standard.object(forKey: naturalScrollingKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: naturalScrollingKey) }
    }

    /// The mouse mode button on the iPhone's trackpad. It shows by itself while AssistiveTouch is on or iOS reports
    /// a mouse; this keeps it there all the time (Settings → Accessibility).
    static let alwaysShowMouseModeKey = "iDesk.alwaysShowMouseMode"
    static var alwaysShowMouseMode: Bool {
        get { UserDefaults.standard.bool(forKey: alwaysShowMouseModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: alwaysShowMouseModeKey) }
    }

    /// Multiplies every scroll: 1 for natural scrolling, -1 for traditional.
    static var scrollDirection: CGFloat { naturalScrolling ? 1 : -1 }
}

/// Settings on the iPhone, used when no display is connected (with one, Settings opens on the desktop and has all
/// of these too): only what is about the iPhone itself, the trackpad and the mouse. Everything about the desktop is
/// in the desktop's Settings, so there is one place for it. (No volume: over HDMI/DisplayPort iOS sends audio at
/// full level and the display or TV sets the volume.)
struct SettingsSheet: View {
    @ObservedObject var model: DesktopModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(InputSettings.pointerKey) private var pointerSpeed = InputSettings.defaultPointer
    @AppStorage(InputSettings.scrollKey) private var scrollSpeed = InputSettings.defaultScroll
    @AppStorage(InputSettings.naturalScrollingKey) private var naturalScrolling = true
    @AppStorage(InputSettings.alwaysShowMouseModeKey) private var alwaysShowMouseMode = false
    @AppStorage("APLite.personalization.settingsAppearance") private var settingsAppearance = 0
    @State private var showMouseCheck = false
    @ObservedObject private var updates = UpdateChecker.shared
    @State private var showCheck = false
    @State private var showWelcome = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SettingsTabContainer(model: model)
                    } label: {
                        Label("System settings", systemImage: "gearshape.2")
                    }
                }

                Section {
                    labeled("Pointer", systemImage: "cursorarrow.motionlines") {
                        Slider(value: $pointerSpeed, in: 0.6...4)
                    }
                    labeled("Scrolling", systemImage: "arrow.up.and.down") {
                        Slider(value: $scrollSpeed, in: 0.8...5)
                    }
                    Picker(selection: $naturalScrolling) {
                        Text("Natural (Mac)").tag(true)
                        Text("Traditional").tag(false)
                    } label: {
                        Label("Scroll direction", systemImage: "arrow.up.arrow.down")
                    }
                    Button("Reset to defaults") {
                        pointerSpeed = InputSettings.defaultPointer
                        scrollSpeed = InputSettings.defaultScroll
                    }
                } header: {
                    Text("Trackpad speed")
                }

                Section {
                    Toggle(isOn: $alwaysShowMouseMode) {
                        Label("Always show the mouse mode button", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    Button { showMouseCheck = true } label: {
                        Label("Mouse check", systemImage: "computermouse")
                    }
                } header: {
                    Text("Accessibility")
                }

                Section("Help") {
                    Button { showWelcome = true } label: {
                        Label("Show the welcome guide", systemImage: "questionmark.circle")
                    }
                    Button { showCheck = true } label: {
                        Label("Check setup", systemImage: "checklist")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About APLite", systemImage: "info.circle")
                    }
                }

                Section {
                    if let r = updates.available {
                        Button { updates.download() } label: {
                            Label(updates.stepText ?? String(localized: "Update to \(r.version)"), systemImage: "arrow.down.circle.fill")
                        }
                        .disabled(updates.step != nil)
                    } else {
                        Button { updates.check(userAsked: true) } label: {
                            Label(updates.checking ? String(localized: "Checking…") : String(localized: "Check for updates"),
                                  systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(updates.checking)
                    }
                } header: {
                    Text(verbatim: "\(APLite.name) \(APLite.displayVersion)")
                } footer: {
                    if let result = updates.lastResult, updates.available == nil { Text(verbatim: result) }
                }
            }
            .sheet(isPresented: $showMouseCheck) { MouseCheckView() }
            .sheet(isPresented: $showCheck) { SetupCheckView() }
            .fullScreenCover(isPresented: $showWelcome) { WelcomeView() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(settingsScheme)
    }

    private var settingsScheme: ColorScheme? {
        switch APLiteSettings.SettingsAppearance(rawValue: settingsAppearance) ?? .system {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    private func labeled<Content: View>(_ title: LocalizedStringKey, systemImage: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage).font(.subheadline)
            content()
        }
        .padding(.vertical, 2)
    }
}
