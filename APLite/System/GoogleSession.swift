import Foundation
import WebKit

/// Google's account cookies (YouTube, Drive, Gmail…). Kept as a small named helper so Settings and
/// tests can talk about "the Google account" without knowing how APLite stores cookies; the actual
/// save is done by AccountCookies, which watches the shared WebKit store for every web window.
enum GoogleSession {
    static var domains: [String] { GoogleDomain.domains }
    static func isGoogleDomain(_ raw: String) -> Bool { GoogleDomain.matches(raw) }

    static func save(completion: ((Int) -> Void)? = nil) {
        AccountCookies.shared.save(domains: domains, completion: completion)
    }
}
