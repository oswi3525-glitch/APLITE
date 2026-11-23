import Foundation
import WebKit

/// A small, local vault for login cookies. WKWebView already persists cookies across launches, but the
/// vault makes login sessions explicit: they can be listed, exported, removed, and restored even if
/// the user clears the website data store or reinstalls APLite.
///
/// The file stays in Application Support. Nothing leaves the device unless the user taps Export.
/// Writes are serialised: the cookie observer can save from a WebKit queue while the user imports a
/// cookie header from the desktop Settings page, and a lost update there looks like a lost account.
struct SavedCookie: Codable, Equatable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expires: Double?
    var secure: Bool
    /// Older vault files have neither field; they default off and are filled in on the next save.
    var httpOnly: Bool
    var sameSite: String?

    enum CodingKeys: String, CodingKey {
        case name, value, domain, path, expires, secure, httpOnly, sameSite
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        value = try c.decode(String.self, forKey: .value)
        domain = try c.decode(String.self, forKey: .domain)
        path = try c.decode(String.self, forKey: .path)
        expires = try c.decodeIfPresent(Double.self, forKey: .expires)
        secure = try c.decodeIfPresent(Bool.self, forKey: .secure) ?? false
        httpOnly = try c.decodeIfPresent(Bool.self, forKey: .httpOnly) ?? false
        sameSite = try c.decodeIfPresent(String.self, forKey: .sameSite)
    }

    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain,
            .path: path.isEmpty ? "/" : path
        ]
        if let expires = expires, expires > 0 { properties[.expires] = Date(timeIntervalSince1970: expires) }
        if secure { properties[.secure] = true }
        if httpOnly { properties[.httpOnly] = true }
        if let sameSite = sameSite { properties[.sameSite] = sameSite }
        return HTTPCookie(properties: properties)
    }

    init(_ cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expires = cookie.expiresDate?.timeIntervalSince1970
        secure = cookie.isSecure
        httpOnly = cookie.isHttpOnly
        // "None" needs Secure on modern sites and is the default when the attribute is absent, so
        // leaving it out on restore is both safer and equivalent.
        if let policy = cookie.sameSitePolicy {
            switch policy {
            case .lax: sameSite = "Lax"
            case .strict: sameSite = "Strict"
            case .none: sameSite = nil
            }
        } else {
            sameSite = nil
        }
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

    private static let lock = NSLock()
    private static var cachedDomains: [[String: Any]]?
    private static var cachedModification: Date?

    static func load() -> [SavedCookie] {
        lock.lock()
        defer { lock.unlock() }
        return unlockedLoad()
    }

    private static func unlockedLoad() -> [SavedCookie] {
        guard let data = try? Data(contentsOf: file),
              let items = try? JSONDecoder().decode([SavedCookie].self, from: data) else { return [] }
        return items
    }

    private static func unlockedWrite(_ items: [SavedCookie]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: file, options: .atomic)
        cachedDomains = nil
        cachedModification = nil
    }

    /// Merges cookies into the vault (same name/domain/path is overwritten) and returns how many
    /// cookies were written — including token refreshes of cookies that were already in the vault.
    @discardableResult
    static func save(_ cookies: [HTTPCookie]) -> Int {
        guard !cookies.isEmpty else { return 0 }
        let written = Set(cookies.map { SavedCookie($0).key }).count
        lock.lock()
        defer { lock.unlock() }
        var items = unlockedLoad()
        var indexByKey: [String: Int] = [:]
        for (i, item) in items.enumerated() { indexByKey[item.key] = i }
        for cookie in cookies {
            let saved = SavedCookie(cookie)
            if let i = indexByKey[saved.key] { items[i] = saved }
            else { items.append(saved); indexByKey[saved.key] = items.count - 1 }
        }
        unlockedWrite(items)
        return written
    }

    @discardableResult
    static func remove(domain rawDomain: String) -> Int {
        guard let domain = CookieImporter.sanitizedDomain(rawDomain) else { return 0 }
        lock.lock()
        defer { lock.unlock() }
        let items = unlockedLoad()
        let kept = items.filter { $0.domain != domain && !$0.domain.hasSuffix("." + domain) }
        let removed = items.count - kept.count
        if removed > 0 { unlockedWrite(kept) }
        return removed
    }

    /// Domains and how many cookies are stored for each, for the Settings page.
    static func domains() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        let modification = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        if let cachedDomains = cachedDomains, cachedModification == modification { return cachedDomains }
        let grouped = Dictionary(grouping: unlockedLoad()) { $0.domain }
        let result = grouped.keys.sorted().map { ["domain": $0, "count": grouped[$0]?.count ?? 0] }
        cachedDomains = result
        cachedModification = modification
        return result
    }

    /// Puts every saved cookie back into WebKit. Called at launch; completion is on the main queue.
    static func restore(completion: @escaping (Int) -> Void = { _ in }) {
        let cookies = load().compactMap { $0.cookie }
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
