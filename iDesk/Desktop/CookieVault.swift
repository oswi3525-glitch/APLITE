import Foundation
import WebKit

/// A small, local vault for the login cookies the user imports. WKWebView already persists cookies
/// across launches, but the vault makes login sessions explicit: they can be listed, exported,
/// removed, and restored even if the user clears the website data store or reinstalls APLite.
///
/// The file stays in Application Support. Nothing leaves the device unless the user taps Export.
struct SavedCookie: Codable, Equatable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expires: Double?
    var secure: Bool

    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain,
            .path: path.isEmpty ? "/" : path
        ]
        if let expires, expires > 0 { properties[.expires] = Date(timeIntervalSince1970: expires) }
        if secure { properties[.secure] = true }
        return HTTPCookie(properties: properties)
    }

    init(_ cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expires = cookie.expiresDate?.timeIntervalSince1970
        secure = cookie.isSecure
    }

    var key: String { "\(domain)\t\(path)\t\(name)" }
}

enum CookieVault {
    private static let file: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("APLite", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cookies.json")
    }()

    static func load() -> [SavedCookie] {
        guard let data = try? Data(contentsOf: file),
              let items = try? JSONDecoder().decode([SavedCookie].self, from: data) else { return [] }
        return items
    }

    private static func write(_ items: [SavedCookie]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// Merges cookies into the vault (same name/domain/path is overwritten) and returns the count.
    @discardableResult
    static func save(_ cookies: [HTTPCookie]) -> Int {
        guard !cookies.isEmpty else { return 0 }
        var items = load()
        var indexByKey: [String: Int] = [:]
        for (i, item) in items.enumerated() { indexByKey[item.key] = i }
        var added = 0
        for cookie in cookies {
            let saved = SavedCookie(cookie)
            if let i = indexByKey[saved.key] { items[i] = saved }
            else { items.append(saved); indexByKey[saved.key] = items.count - 1; added += 1 }
        }
        write(items)
        return added
    }

    @discardableResult
    static func remove(domain rawDomain: String) -> Int {
        guard let domain = CookieImporter.sanitizedDomain(rawDomain) else { return 0 }
        let items = load()
        let kept = items.filter { $0.domain != domain && !$0.domain.hasSuffix("." + domain) }
        let removed = items.count - kept.count
        if removed > 0 { write(kept) }
        return removed
    }

    /// Domains and how many cookies are stored for each, for the Settings page.
    static func domains() -> [[String: Any]] {
        let grouped = Dictionary(grouping: load()) { $0.domain }
        return grouped.keys.sorted().map { ["domain": $0, "count": grouped[$0]?.count ?? 0] }
    }

    /// Puts every saved cookie back into WebKit. Called at launch; completion is on the main queue.
    static func restore(completion: @escaping (Int) -> Void = { _ in }) {
        let cookies = load().compactMap(\.cookie)
        CookieImporter.install(cookies, completion: completion)
    }

    /// A JSON file for the share sheet (a machine-readable backup of saved logins).
    static func exportFile() -> URL? {
        let items = load()
        guard !items.isEmpty, let data = try? JSONEncoder().encode(items) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("APLite-cookies-\(Int(Date().timeIntervalSince1970)).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }
}
