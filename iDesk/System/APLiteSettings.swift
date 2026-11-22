import Foundation

/// The ten setting groups of the independent APLite desktop. Every value is real and persisted in
/// UserDefaults under an `APLite.` prefix; existing iDesk keys are deliberately left alone so old
/// installations keep their settings. This file is the single place modules read their options.
enum SettingsGroup: String, CaseIterable, Identifiable {
    case personalization, security, power, performance, applications, storage, display, input, certificates, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personalization: return String(localized: "Personalization")
        case .security: return String(localized: "Security")
        case .power: return String(localized: "Power")
        case .performance: return String(localized: "Performance")
        case .applications: return String(localized: "Applications")
        case .storage: return String(localized: "Storage")
        case .display: return String(localized: "Display")
        case .input: return String(localized: "Input")
        case .certificates: return String(localized: "Certificates")
        case .system: return String(localized: "System")
        }
    }

    var symbol: String {
        switch self {
        case .personalization: return "paintbrush"
        case .security: return "lock.shield"
        case .power: return "power"
        case .performance: return "gauge.with.dots.needle.50percent"
        case .applications: return "square.grid.2x2"
        case .storage: return "folder"
        case .display: return "display"
        case .input: return "keyboard"
        case .certificates: return "key.fill"
        case .system: return "gearshape.2"
        }
    }
}

enum APLiteSettings {
    private static let store = UserDefaults.standard
    private static func key(_ group: String, _ name: String) -> String { "APLite.\(group).\(name)" }

    static func bool(_ group: String, _ name: String, default defaultValue: Bool = false) -> Bool {
        guard let value = store.object(forKey: key(group, name)) as? Bool else { return store.bool(forKey: key(group, name)) || defaultValue }
        return value
    }
    static func set(_ group: String, _ name: String, _ value: Bool) { store.set(value, forKey: key(group, name)) }
    static func number(_ group: String, _ name: String, default defaultValue: Int) -> Int {
        store.object(forKey: key(group, name)) as? Int ?? defaultValue
    }
    static func set(_ group: String, _ name: String, _ value: Int) { store.set(value, forKey: key(group, name)) }
    static func string(_ group: String, _ name: String, default defaultValue: String = "") -> String {
        store.string(forKey: key(group, name)) ?? defaultValue
    }
    static func set(_ group: String, _ name: String, _ value: String) { store.set(value, forKey: key(group, name)) }

    enum Security {
        static var lockOnLaunch: Bool { get { APLiteSettings.bool("security", "lockOnLaunch") } set { APLiteSettings.set("security", "lockOnLaunch", newValue) } }
        static var lockWhenSleeping: Bool { get { APLiteSettings.bool("security", "lockOnSleep", default: true) } set { APLiteSettings.set("security", "lockOnSleep", newValue) } }
        static var authenticateOnWake: Bool { get { APLiteSettings.bool("security", "authOnWake", default: true) } set { APLiteSettings.set("security", "authOnWake", newValue) } }
        static var autoLockMinutes: Int { get { APLiteSettings.number("security", "autoLock", default: 15) } set { APLiteSettings.set("security", "autoLock", newValue) } }
        static var useOwnPasscode: Bool { get { APLiteSettings.bool("security", "ownPasscode") } set { APLiteSettings.set("security", "ownPasscode", newValue) } }
        static let autoLockOptions = [0, 1, 2, 5, 10, 15, 30, 60]
    }

    enum Power {
        static var closeGuestsOnShutdown: Bool { get { APLiteSettings.bool("power", "closeGuests", default: true) } set { APLiteSettings.set("power", "closeGuests", newValue) } }
        static var restoreSessionOnLaunch: Bool { get { APLiteSettings.bool("power", "restoreSession", default: true) } set { APLiteSettings.set("power", "restoreSession", newValue) } }
        static var suspendWorkOnSleep: Bool { get { APLiteSettings.bool("power", "suspendWork", default: true) } set { APLiteSettings.set("power", "suspendWork", newValue) } }
    }

    enum Performance {
        /// Target ceiling for the whole APLite process (guest apps included). Soft: iOS decides the real limit.
        static var memoryTargetMB: Int { get { APLiteSettings.number("performance", "memoryTargetMB", default: 1024) } set { APLiteSettings.set("performance", "memoryTargetMB", max(256, newValue)) } }
        static var warningPercent: Int { get { APLiteSettings.number("performance", "warnPercent", default: 80) } set { APLiteSettings.set("performance", "warnPercent", min(99, max(50, newValue))) } }
        static var releaseCachesWhenIdle: Bool { get { APLiteSettings.bool("performance", "releaseCaches", default: true) } set { APLiteSettings.set("performance", "releaseCaches", newValue) } }
        static var detectLeaks: Bool { get { APLiteSettings.bool("performance", "detectLeaks", default: true) } set { APLiteSettings.set("performance", "detectLeaks", newValue) } }
        static let memoryTargets = [512, 768, 1024, 1536]
    }

    enum Certificates {
        static var rememberChoice: Bool { get { APLiteSettings.bool("certificates", "remember") } set { APLiteSettings.set("certificates", "remember", newValue) } }
    }

    enum System {
        static var lastShutdown: Date? {
            get { (store.object(forKey: key("system", "lastShutdown")) as? Date) }
            set { store.set(newValue, forKey: key("system", "lastShutdown")) }
        }
        static var cleanShutdown: Bool { get { APLiteSettings.bool("system", "cleanShutdown", default: true) } set { APLiteSettings.set("system", "cleanShutdown", newValue) } }
        /// Pages open at the last clean shutdown, so a fresh launch can restore the desktop.
        static var savedSession: [String] {
            get { store.array(forKey: key("system", "session")) as? [String] ?? [] }
            set { store.set(newValue, forKey: key("system", "session")) }
        }
    }
}
