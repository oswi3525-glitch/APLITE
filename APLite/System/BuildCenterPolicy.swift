import Foundation

/// Pure rules for Build Center's GitHub requests. Foundation only so the standalone unit-test
/// target can verify them without network access.
enum BuildCenterPolicy {
    static let apiHost = "api.github.com"
    static let artifactHosts = ["api.github.com", "objects.githubusercontent.com"]

    /// The artifact download URL comes from an API response. Only send the Bearer token to hosts
    /// GitHub actually uses for artifacts; a compromised response must not exfiltrate the token.
    static func allowsToken(for url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return artifactHosts.contains(host)
    }

    /// owner/repo come from user input in Build Center settings; escape each path segment.
    static func encodedSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}
