import Foundation

extension Bundle {
    /// APLite's own bundle. Bundle.main is not: while an iOS app runs inside APLite it is that app's bundle, so APLite's
    /// version and texts read from it would be the app's (YouTube's version in Settings, English texts, an update
    /// check against the wrong version).
    static let aplite = Bundle(path: (OwnSignature.executablePath as NSString).deletingLastPathComponent) ?? .main
}

extension String {
    /// APLite's texts, looked up in APLite's own bundle (see Bundle.aplite). Shadows Foundation's initializer for this
    /// module, so every `String(localized:)` in APLite uses it.
    init(localized key: String.LocalizationValue, table: String? = nil) {
        self.init(localized: key, table: table, bundle: .aplite)
    }
}
