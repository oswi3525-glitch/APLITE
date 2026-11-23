import Foundation
import WebKit

/// Every web window (including the ones on the external monitor) uses the shared
/// `WKWebsiteDataStore.default()`. Watching that store means a login in Facebook, Zalo, Gmail or any
/// other web app is copied into APLite's local vault no matter which screen or scene it happened on.
/// The old code only saved Google cookies, and only when the *phone* scene went into the background —
/// a login made while the iPhone lay flat next to the monitor was therefore never vaulted.
final class AccountCookies: NSObject, WKHTTPCookieStoreObserver {
    static let shared = AccountCookies()

    private var started = false
    private var debounce: DispatchWorkItem?
    /// The WebKit store calls the observer for every token refresh. Remember the last set we wrote so
    /// repeated notifications for the same login do not rewrite the vault file over and over.
    private var lastSignature = ""

    /// Register before any WKWebView is created (from AppDelegate) so we see the first changes too.
    func start() {
        guard !started else { return }
        started = true
        WKWebsiteDataStore.default().httpCookieStore.add(self)
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        // A sign-in sets a burst of cookies. Wait for the burst to settle before reading them all.
        debounce?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.flush() }
        debounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    /// Saves right now. Safe from any queue; the completion is on the main queue.
    func flush(completion: ((Int) -> Void)? = nil) {
        debounce?.cancel()
        debounce = nil
        save(domains: nil, force: false, completion: completion)
    }

    /// Saves cookies for an explicit list of domains, or all login cookies when `domains` is nil.
    /// `force` is false only for the automatic observer path: a sign-in burst can notify the store
    /// several times with identical cookies, and rewriting the vault each time is pure I/O churn.
    /// Manual "Save all accounts" stays forced so a refreshed token is still reported as saved.
    func save(domains: [String]? = nil, force: Bool = true, completion: ((Int) -> Void)? = nil) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            let chosen: [HTTPCookie]
            if let domains = domains {
                chosen = cookies.filter { AccountCookies.matches($0.domain, anyOf: domains) }
            } else {
                chosen = AccountCookies.loginCookies(cookies)
            }
            let signature = AccountCookies.signature(of: chosen)
            let changed = force || (signature != (self?.lastSignature ?? ""))
            let count = changed ? CookieVault.save(chosen) : chosen.count
            if let self = self, !chosen.isEmpty { self.lastSignature = signature }
            DispatchQueue.main.async { completion?(count) }
        }
    }

    // MARK: - What is worth saving

    /// Hosts of the bundled web apps, any site the user installed as a web app, Google services, and
    /// domains already in the vault. Cookies from those sites are account sessions, not ad tracking.
    static func knownDomains() -> [String] {
        var set = Set(GoogleDomain.domains.map { $0.lowercased() })
        for app in BuiltInWebApp.allCases {
            if let host = URL(string: app.url)?.host?.lowercased() { set.insert(host) }
        }
        for entry in WebApps.shared.all {
            if let host = URL(string: entry.url)?.host?.lowercased() { set.insert(host) }
        }
        for item in CookieVault.domains() {
            if let domain = item["domain"] as? String { set.insert(domain.lowercased()) }
        }
        return set.sorted()
    }

    /// Known-site cookies, plus auth-named cookies from any other site (GitHub, a forum, a bank…).
    /// Bounded in size and count so the vault stays a small backup, never a copy of the whole jar.
    static func loginCookies(_ cookies: [HTTPCookie]) -> [HTTPCookie] {
        let domains = knownDomains()
        let authNames = ["session", "sess", "sid", "auth", "token", "login", "passport",
                         "remember", "userid", "user_id", "uid", "csrf", "xsrf"]
        let selected = cookies.filter { cookie in
            guard cookie.value.count <= 8192, cookie.name.count <= 256 else { return false }
            if matches(cookie.domain, anyOf: domains) { return true }
            let name = cookie.name.lowercased()
            return authNames.contains { name.contains($0) }
        }
        return Array(selected.prefix(600))
    }

    static func matches(_ rawDomain: String, anyOf domains: [String]) -> Bool {
        let host = rawDomain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domains.contains { base in
            let root = base.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == root || host.hasSuffix("." + root)
        }
    }

    private static func signature(of cookies: [HTTPCookie]) -> String {
        cookies.map { "\($0.domain)\t\($0.path)\t\($0.name)\t\($0.value.hashValue)" }
               .joined(separator: "\n")
    }
}
