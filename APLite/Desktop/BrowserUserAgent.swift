import Foundation

/// Completes the UA identity that WebKit builds for desktop-mode pages.
///
/// With `preferredContentMode = .desktop` and no `applicationNameForUserAgent`, WebKit emits
/// `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)` — it omits
/// the `Version/<n> … Safari/<build>` tokens that real Safari sends. Google's browser-support check
/// treats that anonymous WebKit client as unknown/outdated and shows the Gmail banner.
///
/// We only add the **real** Safari version derived from the device's iOS version. WebKit still
/// generates the engine token itself, so this never claims a different engine or a newer version.
/// Kept Foundation-only so it is unit testable without UIKit.
enum BrowserUserAgent {
    /// e.g. `Version/17.4 Safari/605.1.15` for iOS 17.4.1.
    static func applicationName(systemVersion: String) -> String {
        let numbers = systemVersion.split(separator: ".").prefix(2).compactMap { Int($0) }
        let major = numbers.first ?? 17
        let minor = numbers.count > 1 ? numbers[1] : 0
        return "Version/\(major).\(minor) Safari/605.1.15"
    }
}
