import Foundation

/// Pure Google-domain matching, unit tested without WebKit or the cookie vault.
enum GoogleDomain {
    static let domains = ["google.com", "google.com.vn", "youtube.com", "gstatic.com", "googleusercontent.com"]

    static func matches(_ raw: String) -> Bool {
        let host = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
