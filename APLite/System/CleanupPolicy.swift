import Foundation

/// Pure rules for the internal cleanup feature. Foundation only, no app singletons, so the
/// standalone unit-test target can compile and verify it.
enum CleanupPolicy {
    enum Category: String, CaseIterable, Identifiable {
        case caches
        case temporaryFiles
        case oldLogs
        case oldDiagnostics
        case buildArtifacts
        case orphanWebAppIcons

        var id: String { rawValue }

        var title: String {
            switch self {
            case .caches: return String(localized: "Guest app caches")
            case .temporaryFiles: return String(localized: "Temporary files")
            case .oldLogs: return String(localized: "Rotated system logs")
            case .oldDiagnostics: return String(localized: "Old diagnostics reports")
            case .buildArtifacts: return String(localized: "Build Center archives")
            case .orphanWebAppIcons: return String(localized: "Unused web app icons")
            }
        }
    }

    /// Classifies a sandbox URL. Returns nil for anything APLite must leave alone (user documents,
    /// installed guest apps, the live log and all other apps' containers).
    static func category(for url: URL) -> Category? {
        let path = url.standardizedFileURL.path
        let name = url.lastPathComponent
        let lower = path.lowercased()
        let lowerName = name.lowercased()
        let inAPLiteArea = lower.contains("/aplite/")

        if lower.contains("/caches/") { return .caches }
        if lower.contains("/tmp/") {
            let temporaryPrefixes = ["export-", "update-", "cert-", "aplite-app-"]
            return temporaryPrefixes.contains { lowerName.hasPrefix($0) } ? .temporaryFiles : nil
        }
        if inAPLiteArea, lower.contains("/logs/"), lowerName.hasPrefix("aplite-system."), lowerName.hasSuffix(".log") {
            return .oldLogs
        }
        if inAPLiteArea, lowerName.hasPrefix("diagnostics-"), lowerName.hasSuffix(".txt") { return .oldDiagnostics }
        if inAPLiteArea, lowerName.hasPrefix("aplite-"), lowerName.hasSuffix(".zip") { return .buildArtifacts }
        return nil
    }

    /// Age rule used for everything except WebView caches (which the user triggers explicitly).
    static func isExpired(_ modified: Date?, days: Int, now: Date = Date()) -> Bool {
        guard let modified else { return true }
        return now.timeIntervalSince(modified) >= Double(days) * 86_400
    }

    /// Never let a cleanup result claim more than APLite's own bounded budget in one pass.
    static func isWithinBudget(_ bytes: UInt64) -> Bool { bytes <= 8 * 1024 * 1024 * 1024 }
}
