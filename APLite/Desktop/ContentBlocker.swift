import WebKit

/// Blocks ads and trackers in web windows (Settings → Browser): requests to known ad and tracking servers are not
/// made, and the empty ad boxes they leave are hidden. On by default. Ads served from a site's own servers (for
/// example YouTube's) are not blocked.
/// The user's own lists: sites always blocked (the site itself and anything it loads from there), and sites where
/// nothing is blocked (YouTube at first: its player does not show when its ad requests fail).
enum ContentBlocker {
    static let key = "iDesk.blockAds"
    private static let builtInKey = "iDesk.blockAds.builtIn", blockedKey = "iDesk.blockAds.blocked", allowedKey = "iDesk.blockAds.allowed"
    static let defaultAllowed = ["youtube.com", "youtube-nocookie.com", "youtu.be"]

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key); applyToOpenTabs() }
    }

    /// The list of ad and tracking servers that comes with APLite.
    static var usesBuiltInList: Bool {
        get { UserDefaults.standard.object(forKey: builtInKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: builtInKey); rebuild() }
    }

    static var blocked: [String] { UserDefaults.standard.stringArray(forKey: blockedKey) ?? [] }
    static var allowed: [String] { UserDefaults.standard.stringArray(forKey: allowedKey) ?? defaultAllowed }

    static var builtInCount: Int { Set(domains).count }

    /// "https://www.Example.com/ads?x" → "example.com/ads"; nil when it is not a site.
    static func site(from text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let r = t.range(of: "://") { t = String(t[r.upperBound...]) }
        if t.hasPrefix("*.") { t.removeFirst(2) }
        if t.hasPrefix("www.") { t.removeFirst(4) }
        t = String(t.prefix { $0 != "?" && $0 != "#" })
        while t.hasSuffix("/") { t.removeLast() }
        let host = t.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        guard host.contains("."), host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == ":" }) else { return nil }
        return t
    }

    /// Adds a site to the block list (`block`) or the allow list, taking it out of the other one.
    @discardableResult
    static func add(_ text: String, block: Bool) -> Bool {
        guard let site = site(from: text) else { return false }
        var b = blocked.filter { $0 != site }, a = allowed.filter { $0 != site }
        if block { b.append(site) } else { a.append(site) }
        save(blocked: b, allowed: a)
        return true
    }

    static func remove(_ site: String) {
        save(blocked: blocked.filter { $0 != site }, allowed: allowed.filter { $0 != site })
    }

    /// "news.example.com" is on the site "example.com" (or "example.com/path").
    private static func host(_ host: String, isOn site: String) -> Bool {
        let h = site.split(separator: "/").first.map(String.init) ?? site
        return host == h || host.hasSuffix("." + h)
    }

    /// The page's site is in the allow list (nothing blocked there).
    static func isAllowed(_ url: URL?) -> Bool {
        guard let h = url?.host?.lowercased() else { return false }
        return allowed.contains { host(h, isOn: $0) }
    }

    /// The menu of a web window: stop or start blocking on this page's site.
    static func toggleAllowed(_ url: URL?) {
        guard let h = url?.host?.lowercased() else { return }
        if isAllowed(url) {
            save(blocked: blocked, allowed: allowed.filter { !host(h, isOn: $0) })
        } else {
            add(h, block: false)
        }
    }

    private static func save(blocked b: [String], allowed a: [String]) {
        UserDefaults.standard.set(b, forKey: blockedKey)
        UserDefaults.standard.set(a, forKey: allowedKey)
        rebuild()
    }

    private static var ruleList: WKContentRuleList?
    private static var compilingID: String?

    /// The compiled rules are named after their content, so WebKit's copy on disk is used again when nothing changed.
    private static var identifier: String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in rulesJSON.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return "iDesk.blocker." + String(h, radix: 36)
    }

    /// Compiles the rules (or finds them compiled), then puts them into the tabs already open.
    static func prepare() {
        guard let store = WKContentRuleListStore.default() else { return }
        let id = identifier
        guard ruleList?.identifier != id, compilingID != id else { return }
        compilingID = id
        let json = rulesJSON
        store.lookUpContentRuleList(forIdentifier: id) { list, _ in
            if let list { finish(list, id: id); return }
            store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) { list, error in
                if let error { NSLog("APLite: ad blocker rules failed: \(error)") }
                finish(list, id: id)
            }
        }
    }

    private static func rebuild() {
        prepare()
        DesktopPages.refresh()
    }

    private static func finish(_ list: WKContentRuleList?, id: String) {
        DispatchQueue.main.async {
            guard compilingID == id else { return }
            compilingID = nil
            let old = ruleList
            ruleList = list ?? ruleList
            applyToOpenTabs(removing: old)
            // Drop older compiled versions from disk.
            WKContentRuleListStore.default()?.getAvailableContentRuleListIdentifiers { ids in
                for other in ids ?? [] where other.hasPrefix("iDesk.blocker") && other != ruleList?.identifier {
                    WKContentRuleListStore.default()?.removeContentRuleList(forIdentifier: other) { _ in }
                }
            }
        }
    }

    /// A new tab: the rules, when on.
    static func apply(to controller: WKUserContentController, removing old: WKContentRuleList? = nil) {
        if let old { controller.remove(old) }
        guard let ruleList else { prepare(); return }
        controller.remove(ruleList)
        if isEnabled { controller.add(ruleList) }
    }

    private static func applyToOpenTabs(removing old: WKContentRuleList? = nil) {
        for w in DesktopModel.shared.windows {
            for tab in w.tabs { apply(to: tab.configuration.userContentController, removing: old) }
        }
    }

    // MARK: Rules

    /// Ad networks and trackers (international and Vietnamese). Blocked only as third-party requests, so the
    /// companies' own sites still open.
    private static let domains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com",
        "google-analytics.com", "amazon-adsystem.com", "adnxs.com", "taboola.com", "outbrain.com", "criteo.com",
        "criteo.net", "pubmatic.com", "rubiconproject.com", "openx.net", "casalemedia.com", "advertising.com",
        "adsrvr.org", "moatads.com", "scorecardresearch.com", "quantserve.com", "zedo.com", "smartadserver.com",
        "yieldmo.com", "sharethrough.com", "teads.tv", "media.net", "popads.net", "popcash.net", "propellerads.com",
        "adsterra.com", "exoclick.com", "juicyads.com", "mgid.com", "revcontent.com", "adform.net", "bidswitch.net",
        "33across.com", "indexww.com", "sonobi.com", "lijit.com", "contextweb.com", "gumgum.com",
        "onclickads.net", "hotjar.com", "yandex.ru/ads", "adcolony.com", "applovin.com", "unityads.unity3d.com",
        "admicro.vn", "adtimaserver.vn", "eclick.vn", "ambientplatform.vn", "yomedia.vn", "adnetwork.vn",
        "adpia.vn", "novanet.vn", "adx.vn", "vietad.vn",
    ]

    /// Boxes ad scripts draw into, hidden even when their request was blocked.
    private static let hiddenSelectors = [
        "ins.adsbygoogle", ".adsbygoogle", "div[id^=\"div-gpt-ad\"]", "iframe[id^=\"google_ads_iframe\"]",
        "[id^=\"taboola-\"]", ".trc_related_container", ".OUTBRAIN", "[data-google-query-id]",
    ]

    /// "^scheme://(any.)host" then the path or the end of the host.
    private static func pattern(_ site: String) -> String {
        let parts = site.split(separator: "/", maxSplits: 1).map(String.init)
        let host = NSRegularExpression.escapedPattern(for: parts[0])
        let path = parts.count > 1 ? "/" + NSRegularExpression.escapedPattern(for: parts[1]) : "[:/]"
        return #"^[^:]+://+([^:/]+\.)?"# + host + path
    }

    private static var rulesJSON: String {
        var rules: [[String: Any]] = []
        if usesBuiltInList {
            // Only as third-party requests, so the companies' own sites still open.
            rules += Array(Set(domains)).sorted().map {
                ["trigger": ["url-filter": pattern($0), "load-type": ["third-party"]], "action": ["type": "block"]]
            }
            rules.append([
                "trigger": ["url-filter": ".*"],
                "action": ["type": "css-display-none", "selector": hiddenSelectors.joined(separator: ", ")],
            ])
        }
        // The user's block list: the site itself too.
        rules += blocked.map { ["trigger": ["url-filter": pattern($0)], "action": ["type": "block"]] }
        // The allow list last: on those sites' pages nothing above applies. (WebKit's patterns have no "|": one per site.)
        let tops = allowed.map { pattern(String($0.split(separator: "/").first ?? Substring($0))) }
        if !tops.isEmpty, !rules.isEmpty {
            rules.append(["trigger": ["url-filter": ".*", "if-top-url": tops], "action": ["type": "ignore-previous-rules"]])
        }
        if rules.isEmpty {   // WebKit refuses an empty list
            rules.append(["trigger": ["url-filter": "^idesk-never-matches:"], "action": ["type": "block"]])
        }
        let data = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

/// The text size of web pages and APLite's pages (Settings → Display), and each tab's own zoom (⌘ + = / − / 0).
/// Done with CSS zoom on the page: the page lays itself out again for the window's width, as in a desktop browser,
/// instead of being magnified past the window's edges (which is what WKWebView.pageZoom does on iOS).
enum PageZoom {
    static let key = "iDesk.pageZoom"
    static let levels: [Double] = [0.9, 1, 1.15, 1.3, 1.5]

    static var standard: CGFloat {
        CGFloat(UserDefaults.standard.object(forKey: key) as? Double ?? 1)
    }

    /// Tabs zoomed with ⌘ + = / −; the others follow the standard size.
    private static var tabZoom: [ObjectIdentifier: CGFloat] = [:]

    static func zoom(of web: WKWebView) -> CGFloat { tabZoom[ObjectIdentifier(web)] ?? standard }

    static func set(_ zoom: CGFloat, for web: WKWebView) {
        tabZoom[ObjectIdentifier(web)] = abs(zoom - standard) < 0.01 ? nil : zoom
        apply(to: web)
    }

    /// A new standard size: every tab not zoomed on its own follows it.
    static func set(_ value: Double) {
        UserDefaults.standard.set(value, forKey: key)
        for w in DesktopModel.shared.windows { for tab in w.tabs { apply(to: tab) } }
    }

    static func forget(_ web: WKWebView) { tabZoom[ObjectIdentifier(web)] = nil }

    /// Sets the page's zoom now and again once its document is there (called when a page starts and finishes).
    static func apply(to web: WKWebView) {
        let z = zoom(of: web)
        let value = abs(z - 1) < 0.01 ? "''" : "'\(z)'"
        web.evaluateJavaScript("""
        (function (z) {
          const set = () => { const d = document.documentElement; if (d && d.style.zoom !== z) d.style.zoom = z; };
          window.__ideskZoom = z ? parseFloat(z) : 1;
          set();
          // apply() runs on both didCommit and didFinish: register the listener only once per document
          // so it does not pile up (and keep old closures alive) on every navigation.
          if (!window.__ideskZoomListener) {
            window.__ideskZoomListener = true;
            document.addEventListener('DOMContentLoaded', () => {
              window.__ideskZoomListener = false;
              set();
            }, { once: true });
          }
        })(\(value))
        """)
    }
}
