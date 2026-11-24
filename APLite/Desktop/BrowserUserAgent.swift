import Foundation

/// Completes the UA identity that WebKit builds for desktop-mode pages.
///
/// With `preferredContentMode = .desktop` and no `applicationNameForUserAgent`, WebKit emits
/// `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)` — it omits
/// the `Version/<n> … Safari/<build>` tokens that real Safari sends. Google's browser-support check
/// treats that anonymous WebKit client as unknown/outdated and shows the Gmail banner.
///
/// Only the `Version/<major>.<minor>` part comes from the device's real OS version (Safari's version
/// tracks iOS since Safari 26): e.g. `Version/27.0 Safari/605.1.15` on iOS 27.0.1. `Safari/605.1.15`
/// is still the desktop-Safari build token reported by current Safari 27 releases. WebKit generates
/// the `AppleWebKit` engine token itself, so this never claims a different engine. When the version
/// string is missing, the real version comes from ProcessInfo — never an invented fallback.
/// Kept Foundation-only so it is unit testable without UIKit.
enum BrowserUserAgent {
    static func applicationName(major: Int, minor: Int) -> String {
        "Version/\(major).\(minor) Safari/605.1.15"
    }

    static func applicationName(systemVersion: String) -> String {
        let numbers = systemVersion.split(separator: ".").prefix(2).compactMap { Int($0) }
        guard let major = numbers.first else { return applicationNameFromProcessInfo() }
        let minor = numbers.count > 1 ? numbers[1] : 0
        return applicationName(major: major, minor: minor)
    }

    static func applicationNameFromProcessInfo() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return applicationName(major: version.majorVersion, minor: version.minorVersion)
    }
}
