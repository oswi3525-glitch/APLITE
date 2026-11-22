import UIKit

/// Well-known web apps that can be installed with one tap. These are **web shortcuts**, not the
/// native iOS apps: running native Zalo / Facebook / Telegram / Chrome requires a decrypted IPA,
/// which the user must supply — APLite never downloads or cracks one.
enum BuiltInWebApp: CaseIterable {
    case chrome, zalo, facebook, telegram

    var title: String {
        switch self {
        case .chrome: return "Chrome"
        case .zalo: return "Zalo"
        case .facebook: return "Facebook"
        case .telegram: return "Telegram"
        }
    }

    var url: String {
        switch self {
        case .chrome: return "https://www.google.com/chrome/"
        case .zalo: return "https://web.zalo.me"
        case .facebook: return "https://www.facebook.com"
        case .telegram: return "https://web.telegram.org"
        }
    }

    var symbol: String {
        switch self {
        case .chrome: return "globe.americas.fill"
        case .zalo: return "bubble.left.and.bubble.right.fill"
        case .facebook: return "person.2.circle.fill"
        case .telegram: return "paperplane.fill"
        }
    }

    var tint: UIColor {
        switch self {
        case .chrome: return .systemBlue
        case .zalo: return .systemBlue
        case .facebook: return UIColor(red: 0.15, green: 0.42, blue: 0.85, alpha: 1)
        case .telegram: return UIColor(red: 0.20, green: 0.62, blue: 0.86, alpha: 1)
        }
    }
}

enum BuiltInWebApps {
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

    private static func icon(for app: BuiltInWebApp) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .bold)
        return UIImage(systemName: app.symbol, withConfiguration: config)?
            .withTintColor(app.tint, renderingMode: .alwaysOriginal)
    }
}
