import SwiftUI

/// Native adapter that turns the existing settings surface into five clearly grouped tabs.
///
/// The System tab is the untouched `SystemSettingsView`, so every legacy control, key and action
/// keeps working exactly as before. The four other tabs add new APLite features without removing
/// or rewriting anything. Desktop HTML settings are deliberately not touched in this phase.
enum SettingsTab: String, CaseIterable, Identifiable {
    case system
    case apps
    case privacy
    case cleanup
    case apstore

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .apps: return "Apps"
        case .privacy: return "Privacy & Security"
        case .cleanup: return "Cleanup & Optimize"
        case .apstore: return "APStore"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "gearshape.2"
        case .apps: return "square.grid.2x2"
        case .privacy: return "lock.shield"
        case .cleanup: return "trash"
        case .apstore: return "bag.fill"
        }
    }
}

struct SettingsTabContainer: View {
    @ObservedObject var model: DesktopModel
    @AppStorage("APLite.personalization.settingsAppearance") private var settingsAppearance = 0
    @State private var selection: SettingsTab = .system

    var body: some View {
        TabView(selection: $selection) {
            SystemSettingsView(model: model)
                .tabItem { Label(SettingsTab.system.title, systemImage: SettingsTab.system.symbol) }
                .tag(SettingsTab.system)

            AppsSettingsView(model: model)
                .tabItem { Label(SettingsTab.apps.title, systemImage: SettingsTab.apps.symbol) }
                .tag(SettingsTab.apps)

            PrivacySettingsView(model: model)
                .tabItem { Label(SettingsTab.privacy.title, systemImage: SettingsTab.privacy.symbol) }
                .tag(SettingsTab.privacy)

            CleanupSettingsView(model: model)
                .tabItem { Label(SettingsTab.cleanup.title, systemImage: SettingsTab.cleanup.symbol) }
                .tag(SettingsTab.cleanup)

            APStoreView(model: model)
                .tabItem { Label(SettingsTab.apstore.title, systemImage: SettingsTab.apstore.symbol) }
                .tag(SettingsTab.apstore)
        }
        .tint(APLiteColors.accent)
        .sensoryFeedback(.selection, trigger: selection)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(scheme)
    }

    private var scheme: ColorScheme? {
        switch APLiteSettings.SettingsAppearance(rawValue: settingsAppearance) ?? .system {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}
