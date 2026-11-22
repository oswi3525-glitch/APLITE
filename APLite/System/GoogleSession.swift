import Foundation
import WebKit

/// Keeps the Google login session explicit and portable inside APLite. WKWebView already persists
/// cookies, but exporting the Google-family cookies into the local vault means a login survives a
/// cleared website data store. Nothing is uploaded anywhere.
enum GoogleSession {
    /// Google / YouTube domains whose login cookies make up one account session.
    static var domains: [String] { GoogleDomain.domains }

    /// Pure matcher (unit tested). Also accepts a host with a leading dot or a subdomain.
    static func isGoogleDomain(_ raw: String) -> Bool { GoogleDomain.matches(raw) }

    /// Copies the current Google cookies from WebKit into the vault. Completion is on the main queue.
    static func save(completion: ((Int) -> Void)? = nil) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let matching = cookies.filter { isGoogleDomain($0.domain) }
            let count = CookieVault.save(matching)
            DispatchQueue.main.async { completion?(count) }
        }
    }
}
