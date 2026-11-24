import Foundation

/// Pure decision + redaction layer for the in-Settings Technical Diagnostics screen.
/// Foundation-only so the mapping is unit tested in the standalone test target.
enum DiagnosticsPolicy {
    enum Severity: Int, Equatable { case info, warning, critical }

    enum Repair: String, Equatable {
        case releaseCaches, discardTabs, closeWindows, tileWindows
        case restoreAudio, clearAudioLog, clearGuestCaches
    }

    struct Finding: Equatable {
        let id: String
        let title: String
        let detail: String
        let severity: Severity
        let repair: Repair?
    }

    /// Builds a short, prioritised list from signals APLite is entitled to read. No process
    /// enumeration, no system log, no guesses about other apps.
    static func findings(openWindows: Int, tabs: Int, backgroundTabs: Int,
                         usedMB: UInt64, peakMB: UInt64, targetMB: UInt64,
                         suspectedLeak: Bool, thermalWarm: Bool,
                         audioInterrupted: Bool, audioErrors: Int,
                         worstUIGap: TimeInterval, longGaps: Int,
                         lastCrash: Bool, freeSpaceLow: Bool) -> [Finding] {
        var result: [Finding] = []
        if lastCrash {
            result.append(Finding(id: "crash", title: "Last session crashed",
                                  detail: "A crash report is on record. A guest app may have been in use.",
                                  severity: .critical, repair: nil))
        }
        if worstUIGap >= 0.5 || longGaps > 0 {
            result.append(Finding(id: "lag", title: "Main-thread stalls observed",
                                  detail: "Long UI gaps were sampled while this screen was open.",
                                  severity: .warning, repair: .discardTabs))
        }
        if suspectedLeak {
            result.append(Finding(id: "leak", title: "Possible memory growth",
                                  detail: "Memory kept growing across samples. Guest apps and web pages share this process.",
                                  severity: .warning, repair: .releaseCaches))
        }
        if usedMB >= targetMB {
            result.append(Finding(id: "memory", title: "Memory target reached",
                                  detail: "APLite is at or above its soft memory target. Closing windows frees the most.",
                                  severity: .warning, repair: .closeWindows))
        }
        if thermalWarm {
            result.append(Finding(id: "thermal", title: "Device is warm",
                                  detail: "Reduce Motion or Performance mode stops unnecessary GPU work.",
                                  severity: .warning, repair: nil))
        }
        if audioInterrupted || audioErrors > 0 {
            result.append(Finding(id: "audio", title: "Audio reported a problem",
                                  detail: "An interruption or error was recorded. Restoring the session may recover sound.",
                                  severity: .warning, repair: .restoreAudio))
        }
        if backgroundTabs >= 3 {
            result.append(Finding(id: "tabs", title: "Many background tabs",
                                  detail: "\(backgroundTabs) tabs are not in front. Setting them aside frees WebKit memory.",
                                  severity: .info, repair: .discardTabs))
        }
        if freeSpaceLow {
            result.append(Finding(id: "storage", title: "Free space is low",
                                  detail: "Clearing APLite-owned caches can help.",
                                  severity: .info, repair: .releaseCaches))
        }
        if result.isEmpty {
            result.append(Finding(id: "ok", title: "No issues detected",
                                  detail: "Based on \(openWindows + tabs) live signals.",
                                  severity: .info, repair: nil))
        }
        return result
    }

    /// Diagnostics must never copy tokens, cookies or passwords into a report the user shares.
    static func redact(_ text: String) -> String {
        var out = text
        // Auth schemes first: otherwise a key rule consumes "Authorization: Bearer" and leaves the token.
        for scheme in ["Bearer", "Basic"] {
            let pattern = "(?i)\(scheme)\\s+[A-Za-z0-9._~+/=-]+"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(out.startIndex..., in: out)
                out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: "\(scheme) [redacted]")
            }
        }
        let keys = ["password", "passwd", "passcode", "pin", "token", "cookie", "authorization",
                    "secret", "client_secret", "clientsecret", "api_key", "apikey", "api-key",
                    "credential", "credentials", "private_key", "privatekey", "session"]
        for key in keys {
            let e = NSRegularExpression.escapedPattern(for: key)
            let patterns = [
                "\"\(e)\"\\s*:\\s*\"[^\"]*\"",              // JSON: "key": "value"
                "\"\(e)\"\\s*:\\s*[^\\s,;}]+",             // JSON with unquoted value
                "\(e)\\s*[=:]\\s*\"?[^\\s,;}\"]+",         // key=value / key: value / URL query
            ]
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(out.startIndex..., in: out)
                    out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: "\(key)=[redacted]")
                }
            }
        }
        return out
    }

    static func truncate(_ text: String, limit: Int = 6000) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }
}
