import UIKit

/// Well-known web apps that can be installed with one tap. These are **web shortcuts**, not the
/// native iOS apps: running native Zalo / Facebook / Telegram / Chrome requires a decrypted IPA,
/// which the user must supply — APLite never downloads or cracks one.
enum BuiltInWebApp: CaseIterable {
    case zalo, facebook, telegram, chrome, youtube, gmail

    var title: String {
        switch self {
        case .zalo: return "Zalo"
        case .facebook: return "Facebook"
        case .telegram: return "Telegram"
        case .chrome: return "Chrome"
        case .youtube: return "YouTube"
        case .gmail: return "Gmail"
        }
    }

    var url: String {
        switch self {
        case .zalo: return "https://web.zalo.me"
        case .facebook: return "https://www.facebook.com"
        case .telegram: return "https://web.telegram.org"
        case .chrome: return "https://www.google.com/chrome/"
        case .youtube: return "https://www.youtube.com"
        case .gmail: return "https://mail.google.com"
        }
    }

    /// Bundled icon drawn by scripts/generate_assets.py; falls back to a glyph for the generic ones.
    var iconName: String? {
        switch self {
        case .zalo: return "ZaloIcon"
        case .facebook: return "FacebookIcon"
        case .telegram: return "TelegramIcon"
        case .chrome, .youtube, .gmail: return nil
        }
    }

    var symbol: String {
        switch self {
        case .zalo: return "bubble.left.and.bubble.right.fill"
        case .facebook: return "person.2.circle.fill"
        case .telegram: return "paperplane.fill"
        case .chrome: return "globe.americas.fill"
        case .youtube: return "play.rectangle.fill"
        case .gmail: return "envelope.fill"
        }
    }

    var tint: UIColor {
        switch self {
        case .zalo: return UIColor(red: 0.04, green: 0.61, blue: 0.94, alpha: 1)
        case .facebook: return UIColor(red: 0.15, green: 0.42, blue: 0.85, alpha: 1)
        case .telegram: return UIColor(red: 0.20, green: 0.62, blue: 0.86, alpha: 1)
        case .chrome: return UIColor(red: 0.30, green: 0.65, blue: 0.30, alpha: 1)
        case .youtube: return UIColor(red: 0.90, green: 0.16, blue: 0.16, alpha: 1)
        case .gmail: return UIColor(red: 0.87, green: 0.28, blue: 0.25, alpha: 1)
        }
    }
}

enum BuiltInWebApps {
    private static let installedKey = "APLite.builtInWebAppsInstalled"

    /// Installs the presets that are not there yet; returns how many were added.
    @discardableResult
    static func installMissing() -> Int {
        var added = 0
        for app in BuiltInWebApp.allCases {
            guard let url = URL(string: app.url), !WebApps.shared.isInstalled(app.url) else { continue }
            WebApps.shared.install(url, title: app.title, icon: icon(for: app))
            added += 1
        }
        return added
    }

    /// Called once at launch so Zalo / Facebook / Telegram really appear on the desktop instead of
    /// waiting for the user to find the button in Settings. Respects a user who removed them later.
    static func installOnFirstLaunchIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: installedKey) else { return }
        UserDefaults.standard.set(true, forKey: installedKey)
        installMissing()
    }

    private static func icon(for app: BuiltInWebApp) -> UIImage? {
        if let name = app.iconName, let image = UIImage(named: name) { return image }
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .bold)
        return UIImage(systemName: app.symbol, withConfiguration: config)?
            .withTintColor(app.tint, renderingMode: .alwaysOriginal)
    }
}
