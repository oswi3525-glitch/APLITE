import Foundation

/// APLite's identity, attribution and repository links.
///
/// The source started as the APLite project (https://github.com/itshieuk/iDesk). APLite is an
/// independent fork: the original author and license are credited everywhere the app identifies
/// itself. Keep this file the single place for the product name so a future rename does not have
/// to touch the guest engine, the settings keys or the Mach-O loader.
enum APLite {
    static let name = "APLite"
    static let fullName = "AirPlayLite"
    static let tagline = "A lightweight desktop for your iPhone or iPad."

    /// The upstream project this fork is based on. Never presented as APLite's own work.
    static let upstreamName = "iDesk"
    static let upstreamAuthor = "itshieuk"
    static let upstreamURL = URL(string: "https://github.com/itshieuk/iDesk")!

    /// `owner/repository` used by the update checker and the crash report link.
    /// Set `APLiteRepository` in Info.plist to point at another fork.
    static var repository: String {
        (Bundle.aplite.object(forInfoDictionaryKey: "APLiteRepository") as? String)
            ?? "oswi3525-glitch/APLITE"
    }

    static var upstreamRepository: String {
        (Bundle.aplite.object(forInfoDictionaryKey: "APLiteUpstreamRepository") as? String)
            ?? "itshieuk/iDesk"
    }

    static var version: String {
        Bundle.aplite.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0"
    }

    /// Optional channel suffix, e.g. "1.1.0 (beta 1)". Set `APLiteReleaseChannel` in Info.plist.
    static var channel: String {
        (Bundle.aplite.object(forInfoDictionaryKey: "APLiteReleaseChannel") as? String) ?? ""
    }

    static var displayVersion: String {
        channel.isEmpty ? version : "\(version) (\(channel))"
    }

    /// The attribution required by the project rules. Shown in Settings → About, About on the
    /// iPhone and in README.md. Do not replace the original author's name with APLite's.
    static let attribution = """
    APLite is an independently developed project based on the original iDesk project by itshieuk.

    Original project:
    https://github.com/itshieuk/iDesk

    APLite introduces independent design changes, improvements, modifications and additional features while acknowledging the original project’s author and contributors.

    APLite is not an official release or endorsement of the original iDesk project.
    """

    /// Short line for narrow UI (the iPhone About screen).
    static let attributionShort = "Based on the original iDesk project by itshieuk."
}
