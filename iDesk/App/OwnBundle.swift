import Foundation

extension Bundle {
    /// iDesk's own bundle. Bundle.main is not: while an iOS app runs inside iDesk it is that app's bundle, so iDesk's
    /// version and texts read from it would be the app's (YouTube's version in Settings, English texts, an update
    /// check against the wrong version).
    static let iDesk = Bundle(path: (OwnSignature.executablePath as NSString).deletingLastPathComponent) ?? .main
}

extension String {
    /// iDesk's texts, looked up in iDesk's own bundle (see Bundle.iDesk). Shadows Foundation's initializer for this
    /// module, so every `String(localized:)` in iDesk uses it.
    init(localized key: String.LocalizationValue, table: String? = nil) {
        self.init(localized: key, table: table, bundle: .iDesk)
    }
}
