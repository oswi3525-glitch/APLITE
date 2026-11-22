import Foundation
import WebKit

/// Imports cookies into APLite's shared WKWebView cookie store.
///
/// iOS does not let one app read Safari's cookie jar, so "import from Safari" means pasting the
/// cookie header you copied from Safari's Web Inspector (or a cookie manager), or importing a
/// Netscape `cookies.txt` from Files. Nothing is sent anywhere: the values go straight into the
/// local `WKWebsiteDataStore` used by every APLite window.
enum CookieImporter {
    enum Failure: LocalizedError {
        case invalidDomain
        case empty

        var errorDescription: String? {
            switch self {
            case .invalidDomain: return String(localized: "Enter a domain such as example.com.")
            case .empty: return String(localized: "No cookies were found in what you pasted.")
            }
        }
    }

    /// Accepts `example.com`, `.example.com` or a pasted URL.
    static func sanitizedDomain(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }
        if value.contains("://") { value = URL(string: value)?.host ?? value }
        if value.hasPrefix(".") { value.removeFirst() }
        if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
        if let port = value.firstIndex(of: ":") { value = String(value[..<port]) }
        guard value == "localhost" || value.contains("."), !value.contains(" ") else { return nil }
        return value
    }

    /// Parses a `Cookie:` header / `document.cookie` string for one domain.
    static func cookies(fromHeader header: String, domain: String) -> [HTTPCookie] {
        let attributes: Set<String> = ["path", "domain", "expires", "max-age", "httponly",
                                       "secure", "samesite", "priority", "partitioned"]
        var result: [HTTPCookie] = []
        for part in header.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, !pair[0].isEmpty, !attributes.contains(pair[0].lowercased()) else { continue }
            let properties: [HTTPCookiePropertyKey: Any] = [
                .name: pair[0], .value: pair[1], .domain: domain, .path: "/", .version: 0
            ]
            if let cookie = HTTPCookie(properties: properties) { result.append(cookie) }
        }
        return result
    }

    /// Parses a Netscape / Mozilla `cookies.txt` (the format exported by most cookie managers).
    static func cookies(fromNetscape text: String) -> [HTTPCookie] {
        var result: [HTTPCookie] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard !line.hasPrefix("#") else { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 7 else { continue }
            let domain = sanitizedDomain(fields[0]) ?? fields[0]
            let name = fields[5], value = fields[6]
            guard !name.isEmpty else { continue }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: domain,
                .path: fields[2].isEmpty ? "/" : fields[2]
            ]
            if let seconds = Double(fields[4]), seconds > 0 { properties[.expires] = Date(timeIntervalSince1970: seconds) }
            if fields[3].uppercased() == "TRUE" { properties[.secure] = true }
            if let cookie = HTTPCookie(properties: properties) { result.append(cookie) }
        }
        return result
    }

    /// Installing is asynchronous; the completion runs on the main queue with the number applied.
    static func install(_ cookies: [HTTPCookie], completion: @escaping (Int) -> Void) {
        guard !cookies.isEmpty else { completion(0); return }
        let store = WKWebsiteDataStore.default().httpCookieStore
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            store.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) { completion(cookies.count) }
    }

    /// Cookies WebKit currently holds for a domain — used by "save login cookies".
    static func currentCookies(for rawDomain: String, completion: @escaping ([HTTPCookie]) -> Void) {
        guard let domain = sanitizedDomain(rawDomain) else { completion([]); return }
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let matching = cookies.filter { $0.domain == domain || $0.domain.hasSuffix("." + domain) }
            DispatchQueue.main.async { completion(matching) }
        }
    }

    static func removeCookies(for rawDomain: String, completion: @escaping (Int) -> Void) {
        guard let domain = sanitizedDomain(rawDomain) else { completion(0); return }
        let store = WKWebsiteDataStore.default().httpCookieStore
        store.getAllCookies { cookies in
            let matching = cookies.filter { $0.domain == domain || $0.domain.hasSuffix("." + domain) }
            let group = DispatchGroup()
            for cookie in matching {
                group.enter()
                store.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) { completion(matching.count) }
        }
    }
}
