import UIKit
import WebKit

/// A window on the desktop: a browser with tabs, one of APLite's own apps (Settings, Files…), or an app installed
/// from an IPA.
final class DeskWindow: NSObject, ObservableObject, Identifiable, WKUIDelegate, WKNavigationDelegate {
    /// One process pool for every web view: fewer WebContent processes, less memory and fewer kills.
    private static let processPool = WKProcessPool()
    /// Tabs already reloaded after a WebContent termination (one automatic retry, then leave it to the user).
    private var recoveredTabs = Set<ObjectIdentifier>()

    enum Kind: Equatable {
        /// Web pages: address bar, tabs, back / forward / reload.
        case browser
        /// One of APLite's own apps (drawn as a page): a title bar only, like any app window.
        case system(DesktopPage)
        /// An iOS app from an IPA.
        case guest
    }

    let id = UUID()
    let kind: Kind
    var isBrowser: Bool { kind == .browser }
    /// A website installed as an app (WebApps): a browser without the address bar, and without tabs unless a page
    /// opened one (a sign-in popup).
    var isWebApp = false
    /// Stable identity for per-app zoom. Never use currentURL/title — redirects change them.
    var webAppKey: String? {
        guard isWebApp else { return nil }
        let key = initialURL.absoluteString
        return WebApps.shared.all.first { Browsing.same($0.url, key) }?.url ?? key
    }
    var showsAddressBar: Bool { isBrowser && !isWebApp && floatingRestore == nil }
    var showsBookmarksBar: Bool {
        showsAddressBar && Browsing.shared.showsBookmarksBar && !Browsing.shared.bookmarks.isEmpty
    }
    /// Floating video (MediaModes.swift): where the window was before it became a small player.
    @Published var floatingRestore: (frame: CGRect, maximized: Bool, snapped: Bool, keepOnTop: Bool)?
    var showsTabs: Bool { isBrowser && (!isWebApp || tabs.count > 1) }
    var systemPage: DesktopPage? { if case let .system(page) = kind { return page } else { return nil } }
    /// The symbol for the taskbar, the switcher and Recent apps when there is no app icon.
    var symbol: String {
        switch kind {
        case .browser: return "globe"
        case let .system(page): return page.symbol
        case .guest: return "app.fill"
        }
    }
    @Published var frame: CGRect
    @Published var title = String(localized: "New window")
    @Published var isMinimized = false
    @Published var isMaximized = false
    /// Stays above the other windows even when another one is focused (window menu → Keep on top).
    @Published var keepOnTop = false
    /// The workspace (virtual desktop) it is on, and whether that is another one than the one shown.
    var workspace = 0
    @Published var isOffDesk = false
    /// On screen: neither minimized nor on another workspace.
    var isShown: Bool { !isMinimized && !isOffDesk }
    var isSnapped = false           // snapped to a half or a quarter of the screen
    var snap: DesktopModel.Snap?    // which one, while isSnapped
    var restoreFrame: CGRect?
    let initialURL: URL
    let guestApp: GuestApp?         // window of an app installed from an IPA
    let guestWindow: UIWindow?
    var isApp: Bool { guestWindow != nil }
    var onChange: (() -> Void)?
    /// The last tab closed itself: the desktop closes the window.
    var onCloseRequest: (() -> Void)?

    // Tabs (web windows)
    @Published private(set) var tabs: [WKWebView] = []
    @Published private(set) var activeTab = 0
    /// The tab shown; nil for an app window.
    var webView: WKWebView? { tabs.indices.contains(activeTab) ? tabs[activeTab] : nil }

    // Fullscreen (requested by the page through the Fullscreen API, see WebFullscreen.swift)
    @Published var isFullscreen = false
    var fullscreenRestore: (frame: CGRect, maximized: Bool, snapped: Bool)?
    var fullscreenFrame: WKFrameInfo?
    var onFullscreen: ((Bool) -> Void)?
    private let fullscreenBridge = WebFullscreenBridge()
    private let filesBridge = FilesBridge()
    private let inputFocusBridge = WebInputFocusBridge()
    /// The file selected in a Files window (for Quick Look), as a path inside Files.
    var selectedFile: String?
    /// Find in page (⌘F): what is being looked for (nil = the find bar is closed), and whether it is on the page.
    @Published var findQuery: String? {
        didSet { if findQuery == nil, oldValue != nil { clearFind() } }
    }
    /// Matches on the page and which one is shown (1-based; 0 = none).
    @Published var findCount = 0
    @Published var findIndex = 0

    /// Marks every match of the find bar's text on the page and scrolls to the current one; `step` moves to the next
    /// (1) or previous (-1) match, 0 starts over for new text. Drawn with CSS highlights, which show without the page
    /// having focus (WebKit's own find only selects, and a page on the display never has focus).
    func runFind(step: Int = 0) {
        guard let web = webView, let q = findQuery else { return }
        web.callAsyncJavaScript(Self.findScript, arguments: ["q": q, "step": step], in: nil, in: .page) { [weak self] result in
            guard let self, let r = try? result.get() as? [String: Any] else { return }
            self.findCount = r["count"] as? Int ?? 0
            self.findIndex = r["index"] as? Int ?? 0
        }
    }

    private func clearFind() {
        findCount = 0
        findIndex = 0
        webView?.callAsyncJavaScript("if (window.CSS && CSS.highlights) { CSS.highlights.delete('idesk-find'); CSS.highlights.delete('idesk-find-now'); } window.__ideskFind = null;",
                                     arguments: [:], in: nil, in: .page, completionHandler: nil)
    }

    private static let findScript = """
    if (!document.getElementById('idesk-find-style')) {
      const st = document.createElement('style'); st.id = 'idesk-find-style';
      st.textContent = '::highlight(idesk-find){background:#ffe066;color:#000}::highlight(idesk-find-now){background:#ff9632;color:#000}';
      (document.head || document.documentElement).appendChild(st);
    }
    let f = window.__ideskFind;
    if (!f || f.q !== q || step === 0) {
      const ranges = [], needle = q.toLowerCase();
      if (needle) {
        const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT, {
          acceptNode: n => { const p = n.parentElement; if (!p) return NodeFilter.FILTER_REJECT;
            const tag = p.tagName; if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT') return NodeFilter.FILTER_REJECT;
            return p.getClientRects().length ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT; } });
        let n;
        while ((n = walker.nextNode()) && ranges.length < 2000) {
          const text = n.nodeValue.toLowerCase(); let i = 0;
          while ((i = text.indexOf(needle, i)) !== -1 && ranges.length < 2000) {
            const r = document.createRange(); r.setStart(n, i); r.setEnd(n, i + needle.length); ranges.push(r); i += needle.length;
          }
        }
      }
      f = window.__ideskFind = { q: q, ranges: ranges, i: 0 };
    } else if (f.ranges.length) {
      f.i = (f.i + step + f.ranges.length) % f.ranges.length;
    }
    if (window.CSS && CSS.highlights && window.Highlight) {
      CSS.highlights.set('idesk-find', new Highlight(...f.ranges));
      if (f.ranges.length) CSS.highlights.set('idesk-find-now', new Highlight(f.ranges[f.i])); else CSS.highlights.delete('idesk-find-now');
    }
    if (f.ranges.length) {
      const rect = f.ranges[f.i].getBoundingClientRect();
      if (rect.top < 60 || rect.bottom > innerHeight - 20) window.scrollBy({ top: rect.top - innerHeight / 3 });
    }
    return { count: f.ranges.length, index: f.ranges.length ? f.i + 1 : 0 };
    """

    /// The folder a Files window shows ("" = the top of Files).
    private(set) var filesFolder = ""
    /// A text field of the Files page has focus (search, rename): Space types instead of opening Quick Look.
    var filesEditing = false

    /// A text field of the tab in front has focus: the desktop's on-screen keyboard follows this.
    @Published private(set) var webEditing = false
    /// Per-tab focus, so switching tabs does not leave the keyboard showing for the wrong page.
    private var editingTabs = Set<ObjectIdentifier>()

    func setEditing(_ web: WKWebView, _ on: Bool) {
        let id = ObjectIdentifier(web)
        if on { editingTabs.insert(id) } else { editingTabs.remove(id) }
        let active = webView.map { editingTabs.contains(ObjectIdentifier($0)) } ?? false
        if webEditing != active { webEditing = active }
    }

    /// Shows a folder of Files in this window.
    func showFolder(_ folder: String) {
        filesFolder = folder
        selectedFile = nil
        filesEditing = false
        refreshFilesPages()
    }
    private let pageBridge = PageBridge()
    private let gamepadBridge = GamepadBridge()

    /// Height of what is above the content: the title bar (with the tabs of a browser), plus a browser's address bar.
    /// None in fullscreen. Clicks, hover and scrolling are placed in the content from it (DesktopModel.localPoint).
    var chromeHeight: CGFloat {
        isFullscreen ? 0 : Layout.titleBar + (showsAddressBar ? Layout.addressBar : 0) + (showsBookmarksBar ? Layout.bookmarksBar : 0)
    }

    // Address bar
    /// What is being typed in the address field; nil while the field is not being edited.
    @Published var addressDraft: String?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    private var activeObservations: [NSKeyValueObservation] = []
    private var titleObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]

    /// The page shown, as it is saved and restored ("idesk://files" for the Files page, and so on).
    var currentURL: URL {
        guard let url = webView?.url else { return initialURL }
        return Self.savedURL(url)
    }

    func url(ofTab i: Int) -> URL {
        if tabs.indices.contains(i), let d = discarded[ObjectIdentifier(tabs[i])] { return Self.savedURL(d.url) }
        guard tabs.indices.contains(i), let url = tabs[i].url else { return initialURL }
        return Self.savedURL(url)
    }

    /// The address to keep for a tab: APLite's pages by their name (Files is a local file), except the text editor,
    /// whose address names the file it edits.
    private static func savedURL(_ url: URL) -> URL {
        guard let page = DesktopPage(url), page != .editor else { return url }
        return page.url
    }

    /// The area below the title bar (and address bar).
    var contentSize: CGSize { CGSize(width: frame.width, height: max(0, frame.height - chromeHeight)) }

    /// Where an app is drawn inside the content area. iPhone apps only lay out for a phone: stretched across a
    /// maximized window they look broken, so there they keep a phone shape in the middle (black on both sides),
    /// as a phone app would look on a big screen. Landscape content (video) goes fullscreen and fills everything.
    var guestRect: CGRect {
        let c = contentSize
        guard isApp, isMaximized, !isFullscreen, c.width > c.height * 0.8,
              !(guestApp.map(Self.fillsWindow) ?? false) else { return CGRect(origin: .zero, size: c) }
        let w = min(c.width, max(430, (c.height * 0.56).rounded()))
        return CGRect(x: ((c.width - w) / 2).rounded(), y: 0, width: w, height: c.height)
    }

    // MARK: Phone shape or the whole window

    private static let fillKey = "iDesk.appFillsWindow"
    private static var iPadApps: [String: Bool] = [:]

    /// Whether a maximized app fills the whole window instead of keeping a phone shape. Apps made for iPad too do
    /// by default (they lay out for big screens), unless they use scenes; the app window's menu changes it per app.
    static func fillsWindow(_ app: GuestApp) -> Bool {
        if let chosen = (UserDefaults.standard.dictionary(forKey: fillKey) as? [String: Bool])?[app.id] { return chosen }
        if let known = iPadApps[app.id] { return known }
        let info = NSDictionary(contentsOf: app.bundleURL.appendingPathComponent("Info.plist"))
        let families = (info?["UIDeviceFamily"] as? [Int]) ?? []
        // An app built on scenes (TikTok) lays out for its scene, which inside APLite is the iPhone's: stretched
        // across a big window it stays phone-sized in a corner, so it keeps the phone shape too.
        let iPad = families.contains(2) && info?["UIApplicationSceneManifest"] == nil
        iPadApps[app.id] = iPad
        return iPad
    }

    func setFillsWindow(_ fill: Bool) {
        guard let app = guestApp else { return }
        var all = (UserDefaults.standard.dictionary(forKey: Self.fillKey) as? [String: Bool]) ?? [:]
        all[app.id] = fill
        UserDefaults.standard.set(all, forKey: Self.fillKey)
        objectWillChange.send()
    }

    /// The tab showing one of APLite's own pages, if any.
    func tab(showing page: DesktopPage) -> Int? {
        tabs.firstIndex { DesktopPage($0.url) == page }
    }

    /// A window hosting a guest app launched by GuestRuntime.
    init(app: GuestApp, window: UIWindow, frame: CGRect) {
        self.frame = frame
        self.initialURL = app.bundleURL
        self.guestApp = app
        self.guestWindow = window
        self.kind = .guest
        super.init()
        title = app.name
    }

    /// A browser window, or the window of one of APLite's own apps when `url` is one of its pages (idesk://settings…)
    /// and `system` is true.
    init(url: URL, frame: CGRect, system: Bool = true) {
        self.frame = frame
        self.initialURL = url
        self.guestApp = nil
        self.guestWindow = nil
        self.kind = system ? DesktopPage(url).map(Kind.system) ?? .browser : .browser
        super.init()
        if let page = systemPage { title = page.windowTitle(for: url) }
        fullscreenBridge.window = self
        filesBridge.window = self
        inputFocusBridge.window = self
        newTab(url)
    }

    deinit {
        // Same sharing guard as detach(_:): a popup may still use a controller owned by this window.
        for tab in tabs where !tabs.contains(where: {
            $0 !== tab && $0.configuration.userContentController === tab.configuration.userContentController
        }) { Self.detachAll(tab) }
    }

    // MARK: Tabs

    func newTab(_ url: URL, activate: Bool = true) {
        let config = WKWebViewConfiguration()
        // A real, versioned Safari identity (derived from iOS) and one shared WebContent process pool.
        // Without applicationNameForUserAgent, WebKit's desktop UA omits Version/Safari and Google
        // classifies APLite as an unsupported browser.
        config.applicationNameForUserAgent = BrowserUserAgent.applicationName(
            systemVersion: UIDevice.current.systemVersion)
        config.processPool = Self.processPool
        config.allowsInlineMediaPlayback = true
        // Pages may start sound from APLite's clicks (which are not touches on the page) and use Web Audio for volume.
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.preferredContentMode = .desktop   // request desktop websites
        config.userContentController.addUserScript(WebFullscreen.script)
        config.userContentController.add(fullscreenBridge, name: WebFullscreen.messageName)
        config.userContentController.add(filesBridge, name: FilesBridge.messageName)
        config.userContentController.add(pageBridge, name: DesktopPages.messageName)
        config.userContentController.addUserScript(DesktopSite.script(screen: DesktopModel.shared.screenSize))
        ContentBlocker.apply(to: config.userContentController)
        config.userContentController.addUserScript(DarkPages.script())
        config.userContentController.addUserScript(FacebookEnhancements.script)
        config.userContentController.addUserScript(WebVolume.script)
        config.userContentController.add(WebAudioBridge.shared, name: WebAudioBridge.messageName)
        config.userContentController.addUserScript(ControllerInput.pageScript)
        config.userContentController.add(gamepadBridge, name: ControllerInput.messageName)
        config.userContentController.addUserScript(WebInputFocusBridge.script)
        config.userContentController.add(inputFocusBridge, name: WebInputFocusBridge.messageName)
        let tab = WKWebView(frame: CGRect(origin: .zero, size: frame.size), configuration: config)
        // Set before the first load: no flash of unzoomed content, survives all navigations.
        PageZoom.apply(to: tab, appKey: webAppKey)
        Self.load(url, in: tab)
        add(tab, activate: activate)
    }

    /// Reopens a tab where it was, instead of always appending it at the end (⌘⇧T).
    func insertTab(_ url: URL, at index: Int) {
        newTab(url, activate: false)
        let last = tabs.count - 1
        guard tabs.indices.contains(index), last > index else { return }
        tabs.insert(tabs.remove(at: last), at: index)
        if activeTab == last { activeTab = index }
        else if activeTab >= index { activeTab += 1 }
        selectTab(activeTab)
    }

    private func add(_ tab: WKWebView, activate: Bool) {
        tab.uiDelegate = self
        tab.navigationDelegate = self
        titleObservations[ObjectIdentifier(tab)] = tab.observe(\.title) { [weak self] wv, _ in
            DispatchQueue.main.async {
                self?.tabTitleChanged()
                Browsing.shared.updateTitle(wv.url, title: wv.title)
            }
        }
        tabs.append(tab)
        if activate || tabs.count == 1 { selectTab(tabs.count - 1) }
        onChange?()
    }

    // MARK: Low memory

    /// Tabs emptied to give memory back (iOS warned it was running out), and the page each showed.
    private var discarded: [ObjectIdentifier: (url: URL, title: String)] = [:]

    /// Empties the tabs not in front (or every tab of a window that is not shown); each loads again when it is
    /// selected, as browsers do. Returns how many.
    func discardBackgroundTabs() -> Int {
        var n = 0
        for (i, tab) in tabs.enumerated() where (i != activeTab || !isShown) && discarded[ObjectIdentifier(tab)] == nil {
            guard let url = tab.url, Browsing.isWebPage(url) else { continue }
            // A sign-in popup owns live OAuth state; discarding it can orphan window.opener.
            if url.host?.lowercased() == "accounts.google.com" { continue }
            discarded[ObjectIdentifier(tab)] = (url, tab.title ?? "")
            tab.loadHTMLString("<html><body style='background:#111'></body></html>", baseURL: nil)
            n += 1
        }
        return n
    }

    func selectTab(_ i: Int) {
        guard tabs.indices.contains(i) else { return }
        if isFullscreen, i != activeTab { exitFullscreen() }
        activeTab = i
        addressDraft = nil
        findQuery = nil                 // match counts belong to the page we just left
        webEditing = editingTabs.contains(ObjectIdentifier(tabs[i]))
        let tab = tabs[i]
        if let d = discarded.removeValue(forKey: ObjectIdentifier(tab)) { tab.load(URLRequest(url: d.url)) }
        updateFavicon(tab)
        activeObservations = [
            tab.observe(\.url) { [weak self] _, _ in DispatchQueue.main.async { self?.onChange?(); self?.objectWillChange.send() } },
            tab.observe(\.canGoBack, options: [.initial]) { [weak self] wv, _ in DispatchQueue.main.async { self?.canGoBack = wv.canGoBack } },
            tab.observe(\.canGoForward, options: [.initial]) { [weak self] wv, _ in DispatchQueue.main.async { self?.canGoForward = wv.canGoForward } },
            tab.observe(\.isLoading, options: [.initial]) { [weak self] wv, _ in DispatchQueue.main.async { self?.isLoading = wv.isLoading } },
        ]
        tabTitleChanged()
        onChange?()
    }

    /// Closes a tab; false if it was the last one (the caller closes the window instead).
    @discardableResult
    func closeTab(_ i: Int) -> Bool {
        guard tabs.count > 1, tabs.indices.contains(i) else { return false }
        let tab = tabs[i]
        tab.stopLoading()
        PageZoom.forget(tab)
        editingTabs.remove(ObjectIdentifier(tab))
        recoveredTabs.remove(ObjectIdentifier(tab))
        discarded.removeValue(forKey: ObjectIdentifier(tab))
        let wasActive = i == activeTab
        if wasActive { findQuery = nil }  // the find bar belongs to a page, not to the window
        detach(tab)
        tabs.remove(at: i)
        titleObservations[ObjectIdentifier(tab)] = nil
        let next = i < activeTab || activeTab >= tabs.count ? max(0, activeTab - 1) : activeTab
        if wasActive { selectTab(next) }
        else {
            activeTab = next            // closing a background tab must not clear an address draft
            webEditing = editingTabs.contains(ObjectIdentifier(tabs[activeTab]))
            onChange?()
        }
        return true
    }

    func title(ofTab i: Int) -> String {
        guard tabs.indices.contains(i) else { return "" }
        if let d = discarded[ObjectIdentifier(tabs[i])], !d.title.isEmpty { return d.title }
        let t = tabs[i].title ?? ""
        if !t.isEmpty { return t }
        if let url = tabs[i].url, url.isFileURL { return url.lastPathComponent }   // a file from Files: its name
        return tabs[i].url?.host ?? String(localized: "New tab")
    }

    // MARK: Site icon

    /// The site's icon (for the taskbar, Recent apps and the switcher), or an app's icon.
    @Published private(set) var favicon: UIImage?
    /// A web app keeps its branded icon in the dock and switcher instead of flipping to a generic
    /// globe (or the site's favicon) while its page is loading.
    var icon: UIImage? {
        if isWebApp {
            let key = initialURL.absoluteString
            if let branded = WebApps.shared.icon(for: key) { return branded }
            if let entry = WebApps.shared.all.first(where: { Browsing.same($0.url, key) }),
               let branded = WebApps.shared.icon(for: entry.url) { return branded }
        }
        return guestApp?.icon ?? favicon
    }
    private static var favicons: [String: UIImage] = [:]
    /// A site's icon, once a page of it was open (for the bookmarks bar).
    static func cachedFavicon(_ url: String) -> UIImage? { URL(string: url)?.host.flatMap { favicons[$0] } }
    private static var faviconsLoading: Set<String> = []

    /// Shows the icon of the site in the active tab: from the cache, else fetched once per site (the page's
    /// apple-touch-icon, which is large and sharp, else its icon link, else /favicon.ico).
    private func updateFavicon(_ tab: WKWebView) {
        guard isBrowser, let url = tab.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host else { favicon = nil; return }
        if let cached = Self.favicons[host] { favicon = cached; return }
        favicon = nil
        guard !tab.isLoading, !Self.faviconsLoading.contains(host) else { return }
        Self.faviconsLoading.insert(host)
        let script = """
        (() => {
          const links = Array.from(document.querySelectorAll('link[rel~="icon"], link[rel="apple-touch-icon"], link[rel="apple-touch-icon-precomposed"], link[rel="shortcut icon"]'));
          const pick = links.find(l => /apple-touch/.test(l.rel)) || links[links.length - 1];
          return pick ? pick.href : new URL('/favicon.ico', location.href).href;
        })()
        """
        tab.evaluateJavaScript(script) { [weak self] result, _ in
            guard let href = result as? String, let iconURL = URL(string: href) else {
                Self.faviconsLoading.remove(host); return
            }
            URLSession.shared.dataTask(with: iconURL) { data, _, _ in
                // A malformed site can serve a huge "favicon". Decode only a bounded payload.
                let usable = (data?.count ?? 0) <= 2 * 1024 * 1024 ? data : nil
                let image = usable.flatMap(UIImage.init(data:))
                DispatchQueue.main.async {
                    Self.faviconsLoading.remove(host)
                    guard let image else { return }
                    // Bound the cache: a long browsing session visits far more hosts than we need
                    // icons for, and every decoded UIImage holds pixels for the whole session.
                    if Self.favicons.count >= 100, let oldest = Self.favicons.keys.first {
                        Self.favicons.removeValue(forKey: oldest)
                    }
                    Self.favicons[host] = image
                    guard let self, self.webView?.url?.host == host else { return }
                    self.favicon = image
                }
            }.resume()
        }
    }

    private func tabTitleChanged() {
        if let page = systemPage { title = page.windowTitle(for: webView?.url ?? initialURL) }   // an app's name, not the page's <title>
        else if isWebApp {
            let key = initialURL.absoluteString
            title = WebApps.shared.all.first { Browsing.same($0.url, key) }?.title ?? title(ofTab: activeTab)
        }
        else if webView != nil { title = title(ofTab: activeTab) }
        objectWillChange.send()
    }

    private func detach(_ tab: WKWebView) {
        // A popup shares its opener's scripts and message handlers: they stay while another tab still uses them.
        let controller = tab.configuration.userContentController
        guard !tabs.contains(where: { $0 !== tab && $0.configuration.userContentController === controller }) else { return }
        Self.detachAll(tab)
    }

    private static func detachAll(_ tab: WKWebView) {
        tab.configuration.userContentController.removeScriptMessageHandler(forName: WebFullscreen.messageName)
        tab.configuration.userContentController.removeScriptMessageHandler(forName: FilesBridge.messageName)
        tab.configuration.userContentController.removeScriptMessageHandler(forName: DesktopPages.messageName)
        tab.configuration.userContentController.removeScriptMessageHandler(forName: ControllerInput.messageName)
        tab.configuration.userContentController.removeScriptMessageHandler(forName: WebAudioBridge.messageName)
        tab.configuration.userContentController.removeScriptMessageHandler(forName: WebInputFocusBridge.messageName)
    }

    /// Opens an address in the tab shown; "idesk://files" is the Files page.
    func load(_ url: URL) {
        guard let webView else { return }
        Self.load(url, in: webView)
    }

    private static func load(_ url: URL, in webView: WKWebView) {
        let url = FileStore.current(url)
        if let page = DesktopPage(url) {
            page.load(in: webView, address: url)
        } else if url.isFileURL, url.standardizedFileURL.path.hasPrefix(FileStore.downloads.standardizedFileURL.path) {
            // A file from Files (opened from it, or restored with the session): WebKit needs read access to it.
            // Text files are read as UTF-8 (WebKit would guess Latin-1 and garble accents and dashes).
            if QuickLook.kind(of: url) == .text, let data = try? Data(contentsOf: url) {
                webView.load(data, mimeType: "text/plain", characterEncodingName: "utf-8", baseURL: url)
            } else {
                webView.loadFileURL(url, allowingReadAccessTo: FileStore.downloads)
            }
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    /// Sends the Files page what its folder holds now (after a download, a deletion, a move…).
    func refreshFilesPages() {
        if let dir = FileStore.resolve(filesFolder), !FileStore.isFolder(dir) { filesFolder = "" }   // deleted
        for tab in tabs where tab.url.map(FileStore.isFilesPage) == true {
            tab.evaluateJavaScript("window.render && render(\(FileStore.state(folder: filesFolder)))")
        }
    }

    /// Asks the page to leave fullscreen (it reports back so APLite restores the window).
    func exitFullscreen() {
        guard let webView else { onFullscreen?(false); return }
        webView.evaluateJavaScript(WebFullscreen.exitScript, in: fullscreenFrame, in: .page) { [weak self] result in
            // The page did not answer (navigated away, iframe gone…): leave on our own.
            if case .failure = result, self?.isFullscreen == true { self?.onFullscreen?(false) }
        }
    }

    // MARK: Navigation

    /// History: every page that finishes loading.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url { Browsing.shared.record(url, title: webView.title) }
        recoveredTabs.remove(ObjectIdentifier(webView))   // a later crash may be retried once again
        // The user script is baked into the tab configuration when it is created; re-apply the
        // current Clean Facebook choice on every new navigation.
        if let host = webView.url?.host?.lowercased(), host.hasSuffix("facebook.com") {
            webView.evaluateJavaScript("window.__apliteFB && window.__apliteFB(\(FacebookEnhancements.enabled))")
        }
        PageZoom.apply(to: webView, appKey: webAppKey)
        if webView === self.webView { updateFavicon(webView) }
        if let url = webView.url, FileStore.isFilesPage(url) { refreshFilesPages() }
    }

    // Navigating while in fullscreen: the new page is no longer fullscreen.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if isFullscreen, webView === self.webView { onFullscreen?(false) }
        PageZoom.apply(to: webView, appKey: webAppKey)
    }

    /// iOS kills WebContent processes under memory pressure. Without this the tab stays blank until
    /// the user notices and reloads manually. Reload once per tab, then leave it alone (no loop).
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let id = ObjectIdentifier(webView)
        guard !recoveredTabs.contains(id), tabs.contains(where: { $0 === webView }) else { return }
        recoveredTabs.insert(id)
        DispatchQueue.main.async { webView.reload() }
    }

    // target=_blank links and window.open: a new tab, as in a desktop browser. The tab is the web view WebKit asks
    // for, made from the configuration it passes: the page that opened it keeps its link to it (window.opener),
    // which sign-in popups ("Sign in with Google / Apple / Facebook") need to hand the result back.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // APLite's own apps have no tabs: the page opens in a browser window.
        guard isBrowser else {
            if let url = navigationAction.request.url { DesktopModel.shared.openWindow(url) }
            return nil
        }
        // The configuration comes from WebKit (it carries window.opener for OAuth). Re-assert our
        // policy on it before creating the popup so sign-in popups get the same real UA and pool.
        configuration.applicationNameForUserAgent = BrowserUserAgent.applicationName(
            systemVersion: UIDevice.current.systemVersion)
        configuration.processPool = Self.processPool
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        let tab = WKWebView(frame: CGRect(origin: .zero, size: frame.size), configuration: configuration)
        PageZoom.apply(to: tab, appKey: webAppKey)   // sign-in popups inherit the app's zoom
        add(tab, activate: true)
        return tab
    }

    /// The page closed itself (window.close(), as a sign-in popup does when it is done): close its tab.
    func webViewDidClose(_ webView: WKWebView) {
        guard let i = tabs.firstIndex(where: { $0 === webView }) else { return }
        if !closeTab(i) { onCloseRequest?() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        // A link to one of APLite's pages (loading one of them also passes here, as "other": let it through).
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url, url.scheme == "idesk" {
            decisionHandler(.cancel)
            DesktopModel.shared.openWindow(url)
            return
        }
        // A link in one of APLite's apps (a file in Files, a page in History) opens in a browser window: the app's
        // window has no address bar or back button to return with.
        if !isBrowser, navigationAction.navigationType == .linkActivated, navigationAction.targetFrame?.isMainFrame != false,
           let url = navigationAction.request.url {
            decisionHandler(.cancel)
            DesktopModel.shared.openWindow(url)
            return
        }
        // A web app stays on its own site: links elsewhere open in a browser window.
        if isWebApp, navigationAction.navigationType == .linkActivated, navigationAction.targetFrame?.isMainFrame != false,
           let url = navigationAction.request.url, let host = url.host, let own = initialURL.host,
           !Self.sameSite(host, own) {
            decisionHandler(.cancel)
            DesktopModel.shared.openWindow(url)
            return
        }
        decisionHandler(.allow)
    }

    /// "mail.google.com" and "accounts.google.com" belong to the same site.
    private static func sameSite(_ a: String, _ b: String) -> Bool {
        func base(_ h: String) -> String { h.split(separator: ".").suffix(2).joined(separator: ".") }
        return base(a) == base(b)
    }

    /// Files the page cannot show (or that the site marks as attachments) are downloaded to Files.
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        // A video or sound file opened on its own: WebKit would show it with AVKit's player, whose volume control
        // registers the iPhone's buttons from the display's window, and UIKit stops APLite for that. Shown instead in a
        // page of APLite's with an ordinary <video> / <audio> element (WebKit's own controls).
        if navigationResponse.isForMainFrame, let url = navigationResponse.response.url,
           let mime = navigationResponse.response.mimeType?.lowercased(), mime.hasPrefix("video/") || mime.hasPrefix("audio/") {
            decisionHandler(.cancel)
            webView.loadHTMLString(Self.mediaPage(url, video: mime.hasPrefix("video/")), baseURL: url)
            return
        }
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
        let attachment = disposition?.lowercased().hasPrefix("attachment") == true
        decisionHandler(navigationResponse.isForMainFrame && (attachment || !navigationResponse.canShowMIMEType)
                        ? .download : .allow)
    }

    private static func mediaPage(_ url: URL, video: Bool) -> String {
        let src = url.absoluteString.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
        let name = url.lastPathComponent.replacingOccurrences(of: "<", with: "&lt;")
        let tag = video ? "<video src=\"\(src)\" controls autoplay playsinline></video>"
                        : "<audio src=\"\(src)\" controls autoplay></audio>"
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width"><title>\(name)</title><style>
        html,body{margin:0;height:100%;background:#000;display:flex;align-items:center;justify-content:center}
        video{max-width:100%;max-height:100%}audio{width:min(600px,90%)}</style></head><body>\(tag)</body></html>
        """
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = Downloads.shared
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = Downloads.shared
    }
}
