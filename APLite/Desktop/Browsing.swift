import Foundation

/// A web page remembered by APLite: a bookmark, a history entry or a shortcut on the desktop.
struct WebEntry: Codable, Equatable {
    var url: String
    var title: String
    var date: Date
}

/// Bookmarks, browsing history and the web pages the user put on the desktop (and in the app menu).
/// Bookmarks and shortcuts are small and live in UserDefaults; history can grow, so it is a JSON file in Library.
final class Browsing: ObservableObject {
    static let shared = Browsing()

    @Published private(set) var bookmarks: [WebEntry] = Browsing.load(Keys.bookmarks)
    @Published private(set) var history: [WebEntry] = Browsing.loadHistory()
    /// Pages added to the desktop and app menu, in the order they were added.
    @Published private(set) var desktopLinks: [WebEntry] = Browsing.load(Keys.desktopLinks)
    /// Built-in shortcuts (Google, YouTube…) the user removed from the desktop.
    @Published private(set) var hiddenShortcuts: [String] = UserDefaults.standard.stringArray(forKey: Keys.hidden) ?? []

    /// The bookmarks bar under a browser window's address bar (as in Chrome), when there are bookmarks.
    @Published var showsBookmarksBar = UserDefaults.standard.object(forKey: Keys.bookmarksBar) as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsBookmarksBar, forKey: Keys.bookmarksBar); DesktopPages.refresh() }
    }

    private enum Keys {
        static let bookmarksBar = "iDesk.bookmarksBar"
        static let bookmarks = "iDesk.bookmarks"
        static let desktopLinks = "iDesk.desktopLinks"
        static let hidden = "iDesk.hiddenShortcuts"
    }
    private static let historyLimit = 1000
    private var historySave: DispatchWorkItem?

    /// Only real web pages are remembered (not APLite's own pages, files or blank pages).
    static func isWebPage(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    // MARK: Bookmarks

    func isBookmarked(_ url: URL) -> Bool { bookmarks.contains { $0.url == url.absoluteString } }

    func toggleBookmark(_ url: URL, title: String) {
        guard Self.isWebPage(url) else { return }
        if isBookmarked(url) {
            bookmarks.removeAll { $0.url == url.absoluteString }
        } else {
            // At the end, as on Chrome's bookmarks bar.
            bookmarks.append(WebEntry(url: url.absoluteString, title: Self.clean(title, url), date: Date()))
        }
        Self.save(bookmarks, Keys.bookmarks)
    }

    func removeBookmark(_ url: String) {
        bookmarks.removeAll { $0.url == url }
        Self.save(bookmarks, Keys.bookmarks)
    }

    // MARK: Desktop shortcuts

    /// "https://site.com/" and "https://site.com" are the same page.
    static func same(_ a: String, _ b: String) -> Bool {
        func trimmed(_ s: String) -> String { s.hasSuffix("/") ? String(s.dropLast()) : s }
        return trimmed(a) == trimmed(b)
    }

    /// The built-in shortcut for this page (Google, YouTube…), if it is one.
    private func builtIn(_ url: String) -> String? {
        DesktopModel.shortcuts.first { Self.same($0.url, url) }?.url
    }

    func isOnDesktop(_ url: String) -> Bool {
        if let key = builtIn(url) { return !hiddenShortcuts.contains(key) }
        return desktopLinks.contains { Self.same($0.url, url) }
    }

    func addToDesktop(_ url: URL, title: String) {
        let key = url.absoluteString
        if let shortcut = builtIn(key) {
            hiddenShortcuts.removeAll { $0 == shortcut }
            UserDefaults.standard.set(hiddenShortcuts, forKey: Keys.hidden)
            return
        }
        guard Self.isWebPage(url), !desktopLinks.contains(where: { Self.same($0.url, key) }) else { return }
        desktopLinks.append(WebEntry(url: key, title: Self.clean(title, url), date: Date()))
        Self.save(desktopLinks, Keys.desktopLinks)
    }

    /// Takes a page off the desktop and the app menu; a built-in shortcut is only hidden.
    func removeFromDesktop(_ url: String) {
        if let shortcut = builtIn(url) {
            if !hiddenShortcuts.contains(shortcut) { hiddenShortcuts.append(shortcut) }
            UserDefaults.standard.set(hiddenShortcuts, forKey: Keys.hidden)
        } else {
            desktopLinks.removeAll { Self.same($0.url, url) }
            Self.save(desktopLinks, Keys.desktopLinks)
        }
    }

    // MARK: History

    /// A page finished loading. Coming back to the page just visited updates that entry instead of adding one.
    func record(_ url: URL, title: String?) {
        guard Self.isWebPage(url) else { return }
        let key = url.absoluteString, name = Self.clean(title ?? "", url)
        if let first = history.first, first.url == key, Date().timeIntervalSince(first.date) < 30 * 60 {
            history[0].date = Date()
            if !(title ?? "").isEmpty { history[0].title = name }
        } else {
            history.insert(WebEntry(url: key, title: name, date: Date()), at: 0)
            if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        }
        scheduleHistorySave()
    }

    /// The page set its title after loading.
    func updateTitle(_ url: URL?, title: String?) {
        guard let url, let title, !title.isEmpty, let first = history.first, first.url == url.absoluteString,
              first.title != title else { return }
        history[0].title = title
        scheduleHistorySave()
    }

    func removeHistory(at date: TimeInterval, url: String) {
        history.removeAll { $0.url == url && abs($0.date.timeIntervalSince1970 * 1000 - date) < 1 }
        scheduleHistorySave()
    }

    func clearHistory() {
        history = []
        scheduleHistorySave()
    }

    // MARK: Storage

    private static func clean(_ title: String, _ url: URL) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? (url.host ?? url.absoluteString) : String(t.prefix(120))
    }

    private static func load(_ key: String) -> [WebEntry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([WebEntry].self, from: data)) ?? []
    }

    private static func save(_ entries: [WebEntry], _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: key)
    }

    private static var historyFile: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("iDeskHistory.json")
    }

    private static func loadHistory() -> [WebEntry] {
        guard let data = try? Data(contentsOf: historyFile) else { return [] }
        return (try? JSONDecoder().decode([WebEntry].self, from: data)) ?? []
    }

    private func scheduleHistorySave() {
        historySave?.cancel()
        let snapshot = history
        let work = DispatchWorkItem {
            try? JSONEncoder().encode(snapshot).write(to: Self.historyFile, options: .atomic)
        }
        historySave = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
    }
}
