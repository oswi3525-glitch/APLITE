import UIKit
import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// APLite's own pages, shown in ordinary desktop windows so they work with the pointer and keyboard like any page:
/// Files (idesk://files), Settings (idesk://settings), Apps (idesk://apps), Bookmarks and history (idesk://history).
enum DesktopPage: String {
    case files, settings, apps, history, editor
    /// The browser's own settings (ads, dark pages, bookmarks bar): from ⋯ in a browser window.
    case browser

    var url: URL { URL(string: "idesk://\(rawValue)")! }

    /// The app's name in its window's title bar and on the taskbar.
    var title: String {
        switch self {
        case .files: return String(localized: "Files")
        case .settings: return String(localized: "Settings")
        case .apps: return String(localized: "Apps")
        case .history: return String(localized: "Bookmarks and history")
        case .editor: return String(localized: "Text editor")
        case .browser: return String(localized: "Browser settings")
        }
    }

    var symbol: String {
        switch self {
        case .files: return "folder.fill"
        case .settings: return "gearshape.fill"
        case .apps: return "shippingbox.fill"
        case .history: return "book.fill"
        case .editor: return "doc.text.fill"
        case .browser: return "globe"
        }
    }

    init?(_ url: URL?) {
        guard let url else { return nil }
        if url.scheme == "idesk", let page = DesktopPage(rawValue: url.host ?? "") { self = page; return }
        if url.isFileURL, FileStore.isFilesPage(url) { self = .files; return }
        return nil
    }

    /// Default window size for the page.
    var windowSize: CGSize {
        switch self {
        case .files: return CGSize(width: 820, height: 640)
        case .settings: return CGSize(width: 640, height: 760)
        case .apps: return CGSize(width: 700, height: 680)
        case .history: return CGSize(width: 780, height: 720)
        case .editor: return CGSize(width: 820, height: 680)
        case .browser: return CGSize(width: 620, height: 700)
        }
    }

    /// Loads the page into a tab. Settings and Apps are drawn from a state APLite sends (see DesktopPages.state).
    /// `address`: the page's full address (the editor's names the file).
    func load(in webView: WKWebView, address: URL? = nil) {
        switch self {
        case .files: webView.loadFileURL(FileStore.writeFilesPage(), allowingReadAccessTo: FileStore.downloads)
        case .settings, .apps, .history, .browser: webView.loadHTMLString(DesktopPages.html(self), baseURL: url)
        case .editor:
            let address = address ?? url
            webView.loadHTMLString(TextEditor.html(for: address), baseURL: address)
        }
    }

    /// The window's title: the app's name, or the file an editor shows.
    func windowTitle(for address: URL?) -> String {
        if self == .editor, let path = address.flatMap(TextEditor.path(of:)) { return (path as NSString).lastPathComponent }
        return title
    }
}

/// Builds the Settings and Apps pages and handles their buttons (on the main thread).
enum DesktopPages {
    static let messageName = "ideskPage"

    // MARK: State sent to the pages

    static func state(_ page: DesktopPage) -> [String: Any] {
        switch page {
        case .apps: return appsState()
        case .history: return historyState()
        case .settings, .files, .editor, .browser: return settingsState()
        }
    }

    private static func historyState() -> [String: Any] {
        let b = Browsing.shared
        let time = DateFormatter(), day = DateFormatter()
        time.timeStyle = .short
        day.dateStyle = .full
        day.doesRelativeDateFormatting = true          // "Today", "Yesterday", then the date
        let bookmarks: [[String: Any]] = b.bookmarks.map {
            ["url": $0.url, "title": $0.title, "host": URL(string: $0.url)?.host ?? "", "desktop": b.isOnDesktop($0.url)]
        }
        let history: [[String: Any]] = b.history.prefix(500).map {
            ["url": $0.url, "title": $0.title, "host": URL(string: $0.url)?.host ?? "",
             "time": time.string(from: $0.date), "day": day.string(from: $0.date), "id": $0.date.timeIntervalSince1970 * 1000]
        }
        return ["bookmarks": bookmarks, "history": history]
    }

    private static func settingsState() -> [String: Any] {
        let m = DesktopModel.shared
        let wallpapers = Wallpapers.all.map { colors in colors.map(cssColor) }
        return [
            "connected": m.isExternalConnected,
            "brightness": Int((m.externalBrightness * 100).rounded()),
            "resolutions": ExternalDisplay.resolutions.map(ExternalDisplay.name),
            "resolution": ExternalDisplay.resolution.map(ExternalDisplay.name) ?? "",
            "current": ExternalDisplay.currentResolution.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "",
            "overscan": ExternalDisplay.fitsOverscan,
            "wallpaper": m.wallpaper,
            "photos": Wallpapers.photos.map { p in
                [p.index, p.name, p.name == "MeadowWallpaper"
                    ? String(localized: "Đồng cỏ (meadow)") : String(localized: "Biển (ocean)")] as [Any]
            },
            "photoThumbs": Dictionary(uniqueKeysWithValues: Wallpapers.photos.compactMap { p in
                bundledThumbnail(p.name).map { ("\(p.index)", $0) }
            }),
            "dynamic": DynamicWallpaper.cssColors(at: Date()),
            "night": NightFilter.mode.rawValue,
            "wallpapers": wallpapers,
            "custom": customWallpaperThumbnail() ?? NSNull(),
            "savedCookies": CookieVault.domains(),
            "wallpaperBlur": Int(m.wallpaperBlur.rounded()),
            "autoHide": m.autoHideTaskbar,
            "performance": m.performanceMode,
            "reduceMotion": m.reduceMotion,
            "dockScale": m.dockScale,
            "dockIcon": m.dockIconScale,
            "dockSpacing": m.dockSpacing,
            "dockOpacity": m.dockOpacity,
            "dockMagnify": m.dockMagnification,
            "dockAppearance": m.dockAppearance,
            "widgets": m.showWidgets,
            "iconSize": m.iconSize,
            "workspaces": m.workspacesEnabled,
            "hotCorners": m.hotCorners,
            "lock": LockSettings.lockEnabled, "saver": LockSettings.saverMinutes, "biometry": LockSettings.biometryName,
            "powerState": PowerManager.shared.state.label,
            "saverStyle": ScreenSaverSettings.style.rawValue,
            "saverMotion": ScreenSaverSettings.motion,
            "saverFade": ScreenSaverSettings.fade,
            "replacements": TextReplacements.all.map { [$0.short, $0.phrase] },
            "zoom": Int((PageZoom.standard * 100).rounded()),
            "zooms": PageZoom.levels.map { Int(($0 * 100).rounded()) },
            "blockAds": ContentBlocker.isEnabled, "bookmarksBar": Browsing.shared.showsBookmarksBar,
            "builtInList": ContentBlocker.usesBuiltInList, "builtInCount": ContentBlocker.builtInCount,
            "blockedSites": ContentBlocker.blocked, "allowedSites": ContentBlocker.allowed,
            "darkPages": DarkPages.isEnabled,
            "dnd": m.doNotDisturb,
            "maxWindows": m.maxWindows,
            "reopenApps": m.reopenApps,
            "pointer": String(format: "%.1f×", Double(InputSettings.pointerSpeed)),
            "scroll": String(format: "%.1f×", Double(InputSettings.scrollSpeed)),
            "natural": InputSettings.naturalScrolling,
            "mouseModeButton": InputSettings.alwaysShowMouseMode,
            "virtualKeyboard": APLiteSettings.Input.virtualKeyboard,
            "keyboardAlwaysVisible": APLiteSettings.Input.keyboardAlwaysVisible,
            "facebookEnhancements": FacebookEnhancements.enabled,
            "version": APLite.displayVersion,
            "liveNotice": LiveUpdate.notice ?? "",
            "autoUpdate": UpdateChecker.shared.automatic,
            "update": UpdateChecker.shared.available?.version ?? "",
            "updateResult": UpdateChecker.shared.stepText ?? (UpdateChecker.shared.checking ? String(localized: "Checking…") : (UpdateChecker.shared.lastResult ?? "")),
        ]
    }

    private static func appsState() -> [String: Any] {
        let store = GuestStore.shared, m = DesktopModel.shared
        let compat = Compatibility.shared
        compat.refresh()
        let apps: [[String: Any]] = store.apps.map { app in
            var (status, tone) = app.status
            if app.name == m.problemApp {
                status = String(localized: "In use when APLite quit last time") + " · " + status
                tone = .bad
            }
            let open = m.windows.contains { $0.guestApp == app }
            return [
                "id": app.id, "name": app.name, "icon": icon(of: app) ?? NSNull(),
                "status": status, "tone": tone.rawValue, "open": open,
                "pinned": m.isPinned(Shortcut(name: app.name, symbol: "", url: "", hue: 0, app: app)),
                // A bundled app can only leave APLite with the next reinstall: "remove" marks it, "keep" unmarks it.
                "removal": !app.isBundled || app.hasPendingUpdate ? "delete" : (app.pendingRemoval ? "keep" : "remove"),
                "compat": compat.entry(for: app.id)?.note ?? "",
                "compatTone": compat.entry(for: app.id).map { $0.status == "works" ? "good" : $0.status == "broken" ? "bad" : "warn" } ?? "",
            ]
        }
        var adding: Any = NSNull()
        if let p = store.installProgress, p.total > 1 {
            adding = String(localized: "Adding \(p.done + 1) of \(p.total)…")
        } else if store.isInstalling {
            adding = String(localized: "Adding…")
        }
        #if targetEnvironment(simulator)
        let canExport = false
        #else
        let canExport = store.hasPendingExport
        #endif
        return [
            "apps": apps,
            "total": store.totalSize > 0 ? ByteCountFormatter.string(fromByteCount: Int64(store.totalSize), countStyle: .file) : "",
            "adding": adding,
            "export": exportProgress.map { Int($0 * 100) } ?? NSNull(),
            "canExport": canExport && exportProgress == nil,
            "known": compat.entries.filter { e in !store.apps.contains { $0.id == e.id } }.map {
                ["name": $0.name, "note": $0.note, "tone": $0.status == "works" ? "good" : $0.status == "broken" ? "bad" : "warn"]
            },
            "caches": store.cachesSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "",
            "cleanPending": store.clearCachesOnLaunch,
            "reinstallOnly": store.apps.contains(where: \.pendingRemoval)
                && !store.apps.contains(where: { !$0.isBundled || $0.hasPendingUpdate }),
        ]
    }

    private static var icons: [String: String] = [:]
    private static func icon(of app: GuestApp) -> String? {
        if let cached = icons[app.bundleURL.path] { return cached }
        guard let data = app.icon?.pngData() else { return nil }
        let url = "data:image/png;base64," + data.base64EncodedString()
        // Very long sessions can install/remove many guest apps; keep this base64 cache bounded.
        if icons.count >= 64 { icons.removeAll() }
        icons[app.bundleURL.path] = url
        return url
    }

    private static var bundledThumbnailCache: [String: String] = [:]
    /// A small cached data URL for a bundled photo, so the Settings wallpaper picker shows the real
    /// image instead of an emoji tile. Rendered once per asset, not per page reload.
    private static func bundledThumbnail(_ name: String) -> String? {
        if let cached = bundledThumbnailCache[name] { return cached }
        guard let image = UIImage(named: name) else { return nil }
        let size = CGSize(width: 192, height: 192 * image.size.height / max(1, image.size.width))
        let small = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = small.jpegData(compressionQuality: 0.6) else { return nil }
        let url = "data:image/jpeg;base64," + data.base64EncodedString()
        bundledThumbnailCache[name] = url
        return url
    }

    private static var customThumbnail: (image: UIImage, url: String)?
    private static func customWallpaperThumbnail() -> String? {
        guard let image = DesktopModel.shared.customWallpaper else { return nil }
        if let c = customThumbnail, c.image === image { return c.url }
        let size = CGSize(width: 192, height: 192 * image.size.height / max(1, image.size.width))
        let small = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = small.jpegData(compressionQuality: 0.7) else { return nil }
        let url = "data:image/jpeg;base64," + data.base64EncodedString()
        customThumbnail = (image, url)
        return url
    }

    private static func cssColor(_ color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgb(\(Int(r * 255)),\(Int(g * 255)),\(Int(b * 255)))"
    }

    // MARK: Updating open pages

    /// Sends the current state to every tab showing Settings or Apps.
    static func refresh() {
        for w in DesktopModel.shared.windows {
            for tab in w.tabs {
                guard let page = DesktopPage(tab.url), page != .files, page != .editor, !tab.isLoading else { continue }
                tab.evaluateJavaScript("window.render && render(\(json(state(page))))")
            }
        }
    }

    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Buttons

    private static var exportProgress: Double?

    static func handle(_ page: DesktopPage, action: String, value: String) {
        let m = DesktopModel.shared
        switch (page == .browser ? .settings : page, action) {
        case (.settings, "brightness"):
            m.externalBrightness = min(1, max(0.2, m.externalBrightness + (Double(value) ?? 0)))
        case (.settings, "resolution"):
            let parts = value.split(separator: "x").compactMap { Double($0) }
            ExternalDisplay.resolution = parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
        case (.settings, "tvMode"):
            // Seen from the sofa: a lower resolution (everything bigger), larger page text and icons.
            if let r = ExternalDisplay.resolutions.filter({ $0.height <= 720 && $0.height >= 600 && $0.width / $0.height > 1.6 })
                .max(by: { $0.height < $1.height }) {
                ExternalDisplay.resolution = r
            }
            PageZoom.set(1.3)
            m.iconSize = 2
            m.showToast(String(localized: "TV mode: 720p, larger text and icons. Pick Automatic under Resolution to go back."))
        case (.settings, "overscan"):
            ExternalDisplay.fitsOverscan.toggle()
        case (.settings, "wallpaper"):
            if let i = Int(value) { m.wallpaper = i }
        case (.settings, "night"):
            if let n = Int(value), let mode = NightFilter.Mode(rawValue: n) { NightFilter.mode = mode }
        case (.settings, "photo"):
            PhotoPicker.present { data in m.setCustomWallpaper(data) }
            m.showToast(String(localized: "Choose a photo on the iPhone."))
        case (.settings, "photoFiles"):
            DocumentPicker.present(types: [.image]) { urls in
                guard let url = urls.first else { return }
                m.setCustomWallpaper(contentsOf: url)
                m.showToast(String(localized: "Wallpaper saved."))
            }
            m.showToast(String(localized: "Choose a picture on the iPhone."))
        case (.settings, "wallpaperBlur"):
            m.wallpaperBlur = DockSettings.clamp(m.wallpaperBlur + (Double(value) ?? 0), to: 0...20)
        case (.settings, "cookieAdd"):
            let parts = value.components(separatedBy: "\u{1}")
            guard parts.count == 2, let domain = CookieImporter.sanitizedDomain(parts[0]) else {
                m.showToast(String(localized: "Enter a domain such as example.com."))
                break
            }
            let cookies = CookieImporter.cookies(fromHeader: parts[1], domain: domain)
            CookieVault.save(cookies)
            CookieImporter.install(cookies) { count in
                m.showToast(count > 0
                    ? String(localized: "Imported \(count) cookies for \(domain).")
                    : String(localized: "No cookies were found in what you pasted."))
            }
        case (.settings, "cookieFile"):
            DocumentPicker.present(types: [.plainText]) { urls in
                guard let url = urls.first, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
                let cookies = CookieImporter.cookies(fromNetscape: text)
                CookieVault.save(cookies)
                CookieImporter.install(cookies) { count in
                    m.showToast(count > 0
                        ? String(localized: "Imported \(count) cookies from the file.")
                        : String(localized: "No cookies were found in what you pasted."))
                }
            }
            m.showToast(String(localized: "Choose a cookies.txt file on the iPhone."))
        case (.settings, "cookieClear"):
            CookieImporter.removeCookies(for: value) { count in
                m.showToast(String(localized: "Removed \(count) cookies."))
            }
        case (.settings, "cookieSaveCurrent"):
            CookieImporter.currentCookies(for: value) { cookies in
                let saved = CookieVault.save(cookies)
                m.showToast(saved > 0
                    ? String(localized: "Saved \(saved) login cookies for \(value).")
                    : String(localized: "No cookies were found for \(value)."))
            }
        case (.settings, "cookieSaveAll"):
            AccountCookies.shared.save { saved in
                m.showToast(saved > 0
                    ? String(localized: "Saved \(saved) login cookies from all web apps.")
                    : String(localized: "No signed-in accounts were found on the desktop yet."))
            }
        case (.settings, "cookieVaultRemove"):
            let removed = CookieVault.remove(domain: value)
            m.showToast(String(localized: "Removed \(removed) saved cookies."))
        case (.settings, "cookieExport"):
            if let file = CookieVault.exportFile() { ShareSheet.present(file) }
            else { m.showToast(String(localized: "No saved cookies to export.")) }
        case (.settings, "systemSettings"): m.phoneSheet = .settings
        case (.settings, "sleep"): PowerManager.shared.sleep()
        case (.settings, "wake"): PowerManager.shared.wake()
        case (.settings, "shutdown"):
            PowerManager.shared.shutdown()
            m.showToast(String(localized: "APLite shut down. Use Restart in Settings or reopen the app."))
        case (.settings, "audioDiagnostics"):
            AudioSessionManager.shared.copyReportToPasteboard()
            m.showToast(String(localized: "Audio diagnostics copied to the iPhone clipboard"))
        case (.settings, "autoHide"): m.autoHideTaskbar.toggle()
        case (.settings, "performanceMode"): m.performanceMode.toggle()
        case (.settings, "reduceMotion"): m.reduceMotion.toggle()
        case (.settings, "dockScale"):
            m.dockScale = DockSettings.clamp(m.dockScale + (Double(value) ?? 0), to: DockSettings.scaleRange)
        case (.settings, "dockIcon"):
            m.dockIconScale = DockSettings.clamp(m.dockIconScale + (Double(value) ?? 0), to: DockSettings.iconScaleRange)
        case (.settings, "dockSpacing"):
            m.dockSpacing = DockSettings.clamp(m.dockSpacing + (Double(value) ?? 0), to: DockSettings.spacingRange)
        case (.settings, "dockOpacity"):
            m.dockOpacity = DockSettings.clamp(m.dockOpacity + (Double(value) ?? 0), to: DockSettings.opacityRange)
        case (.settings, "dockMagnify"): m.dockMagnification.toggle()
        case (.settings, "dockAppearance"):
            if let n = Int(value), DockAppearance(rawValue: n) != nil { m.dockAppearance = n }
        case (.settings, "upstream"):
            m.openWindow(APLite.upstreamURL)
        case (.settings, "aplite"):
            if let url = URL(string: "https://github.com/\(APLite.repository)") { m.openWindow(url) }
        case (.settings, "widgets"): m.showWidgets.toggle()
        case (.settings, "iconSize"): if let n = Int(value) { m.iconSize = min(max(n, 0), 2) }
        case (.settings, "dnd"): m.doNotDisturb.toggle()
        case (.settings, "workspaces"): m.workspacesEnabled.toggle()
        case (.settings, "reopenApps"): m.reopenApps.toggle()
        case (.settings, "hotCorners"): m.hotCorners.toggle()
        case (.settings, "lock"): LockSettings.lockEnabled.toggle()
        case (.settings, "saver"): if let n = Int(value) { LockSettings.saverMinutes = n; m.lastInput = Date() }
        case (.settings, "saverStyle"):
            if let n = Int(value), ScreenSaverStyle(rawValue: n) != nil {
                ScreenSaverSettings.style = ScreenSaverStyle(rawValue: n)!
                m.objectWillChange.send()
            }
        case (.settings, "saverMotion"):
            ScreenSaverSettings.motion.toggle()
            m.objectWillChange.send()
        case (.settings, "saverFade"):
            ScreenSaverSettings.fade += Double(value) ?? 0
            m.objectWillChange.send()
        case (.settings, "lockNow"): m.lockDesktop(force: true)
        case (.settings, "addReplacement"):
            let parts = value.components(separatedBy: "\u{1}")
            if parts.count == 2 { TextReplacements.add(parts[0], parts[1]) }
        case (.settings, "removeReplacement"): TextReplacements.remove(value)
        case (.settings, "zoom"): if let n = Double(value) { PageZoom.set(n / 100) }
        case (.settings, "blockAds"): ContentBlocker.isEnabled.toggle()
        case (.settings, "builtInList"): ContentBlocker.usesBuiltInList.toggle()
        case (.settings, "bookmarksBar"): Browsing.shared.showsBookmarksBar.toggle()
        case (.settings, "browserSettings"): m.openPage(.browser)
        case (.settings, "blockSite"), (.settings, "allowSite"):
            if !ContentBlocker.add(value, block: action == "blockSite") {
                m.showToast(String(localized: "Type a site such as example.com."))
            }
        case (.settings, "unlistSite"): ContentBlocker.remove(value)
        case (.settings, "darkPages"): DarkPages.isEnabled.toggle()
        case (.settings, "autoUpdate"): UpdateChecker.shared.automatic.toggle()
        case (.settings, "checkUpdate"): UpdateChecker.shared.check(userAsked: true)
        case (.settings, "downloadUpdate"): UpdateChecker.shared.download()
        case (.settings, "guide"):
            m.phoneSheet = .welcome
            m.showToast(String(localized: "The guide is open on the iPhone."))
        case (.settings, "maxWindows"):
            if let n = Int(value) { m.maxWindows = n }
        case (.settings, "pointer"):
            change(InputSettings.pointerKey, by: Double(value) ?? 0, default: InputSettings.defaultPointer, in: 0.6...4)
        case (.settings, "scroll"):
            change(InputSettings.scrollKey, by: Double(value) ?? 0, default: InputSettings.defaultScroll, in: 0.8...6)
        case (.settings, "natural"):
            InputSettings.naturalScrolling = value == "1"
        case (.settings, "mouseModeButton"):
            InputSettings.alwaysShowMouseMode.toggle()
        case (.settings, "virtualKeyboard"):
            APLiteSettings.Input.virtualKeyboard = !APLiteSettings.Input.virtualKeyboard
        case (.settings, "keyboardAlwaysVisible"):
            APLiteSettings.Input.keyboardAlwaysVisible = !APLiteSettings.Input.keyboardAlwaysVisible
            m.objectWillChange.send()
        case (.settings, "facebookEnhancements"):
            FacebookEnhancements.enabled = !FacebookEnhancements.enabled
        case (.settings, "resetSpeeds"):
            UserDefaults.standard.removeObject(forKey: InputSettings.pointerKey)
            UserDefaults.standard.removeObject(forKey: InputSettings.scrollKey)
        case (.history, "unbookmark"):
            Browsing.shared.removeBookmark(value)
        case (.history, "desktop"):
            if let url = URL(string: value) {
                if Browsing.shared.isOnDesktop(value) { Browsing.shared.removeFromDesktop(value) }
                else { Browsing.shared.addToDesktop(url, title: Browsing.shared.bookmarks.first { $0.url == value }?.title ?? "") }
            }
        case (.history, "forget"):
            // "<milliseconds> <url>"
            let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
            if parts.count == 2, let ms = Double(parts[0]) { Browsing.shared.removeHistory(at: ms, url: parts[1]) }
        case (.history, "clear"):
            Browsing.shared.clearHistory()
        case (.apps, "open"):
            if let app = GuestStore.shared.apps.first(where: { $0.id == value }) { m.openApp(app) }
        case (.apps, "pin"):
            if let app = GuestStore.shared.apps.first(where: { $0.id == value }) {
                m.togglePin(Shortcut(name: app.name, symbol: "app.fill", url: "", hue: 0.5, app: app))
            }
        case (.apps, "delete"):
            if let app = GuestStore.shared.apps.first(where: { $0.id == value }) {
                if let w = m.windows.first(where: { $0.guestApp == app }) { m.close(w) }
                GuestStore.shared.remove(app)
            }
        case (.apps, "remove"), (.apps, "keep"):
            if let app = GuestStore.shared.apps.first(where: { $0.id == value }) { GuestStore.shared.toggleRemoval(app) }
        case (.apps, "add"):
            DocumentPicker.present(completion: addPicked)
            m.showToast(String(localized: "Choose the IPA files on the iPhone."))
        case (.apps, "export"):
            export()
        case (.apps, "report"):
            if let app = GuestStore.shared.apps.first(where: { $0.id == value }), let url = Compatibility.reportURL(for: app) {
                m.openWindow(url)
            }
        case (.apps, "clearCaches"):
            GuestStore.shared.clearCachesOnLaunch.toggle()
            if GuestStore.shared.clearCachesOnLaunch {
                m.showToast(String(localized: "The apps' caches are cleared the next time APLite opens."))
            }
        case (.apps, "advanced"):
            m.phoneSheet = .apps
            m.showToast(String(localized: "Certificates are on the iPhone screen."))
        default:
            break
        }
        refresh()
    }

    private static func change(_ key: String, by step: Double, default value: Double, in range: ClosedRange<Double>) {
        let current = UserDefaults.standard.object(forKey: key) as? Double ?? value
        UserDefaults.standard.set(min(range.upperBound, max(range.lowerBound, current + step)), forKey: key)
    }

    private static func addPicked(_ urls: [URL]) {
        let m = DesktopModel.shared
        let files = CertificateFiles.collect(urls)
        guard !files.ipas.isEmpty else {
            m.showToast(String(localized: "No IPA file chosen. Certificates are imported in Apps on the iPhone."))
            return
        }
        GuestStore.shared.install(ipas: files.ipas) { results in
            let added = results.filter { (try? $0.result.get()) != nil }.count
            #if targetEnvironment(simulator)
            m.showToast(GuestStore.summary(of: results))
            #else
            if GuestStore.canLoadOutsideBundle || added < results.count {
                m.showToast(GuestStore.summary(of: results))
            } else {
                export()      // as on the iPhone: package everything at once for the signing app
            }
            #endif
            refresh()
        }
        refresh()
    }

    /// Packages APLite with the new apps, then opens the share sheet on the iPhone to pick the signing app.
    private static func export() {
        guard exportProgress == nil else { return }
        exportProgress = 0
        refresh()
        GuestStore.shared.exportForESign(progress: { value in
            DispatchQueue.main.async { if exportProgress != nil { exportProgress = value; refresh() } }
        }, completion: { result in
            exportProgress = nil
            refresh()
            switch result {
            case .success(let file):
                ShareSheet.present(file)
                DesktopModel.shared.showToast(String(localized: "Pick ESign (or your signing app) on the iPhone."))
            case .failure(let error):
                DesktopModel.shared.showToast(String(localized: "Could not create the file: \(error.localizedDescription)"))
            }
        })
    }

    // MARK: HTML

    static func html(_ page: DesktopPage) -> String {
        let strings: [String: String] = page == .history ? [
            "title": String(localized: "Bookmarks and history"),
            "bookmarks": String(localized: "Bookmarks"), "history": String(localized: "History"),
            "noBookmarks": String(localized: "No bookmarks yet. Click ☆ in a window's address bar to add the page."),
            "noHistory": String(localized: "No history."), "search": String(localized: "Search history"),
            "clear": String(localized: "Clear history"), "confirm": String(localized: "Click again"),
            "toDesktop": String(localized: "Add to desktop"), "onDesktop": String(localized: "On the desktop"),
            "remove": String(localized: "Remove"),
        ] : page == .apps ? [
            "title": String(localized: "Apps"),
            "add": String(localized: "Add IPA files…"),
            "empty": String(localized: "No apps yet. Add a decrypted IPA file, or download one and install it from Files."),
            "howTo": String(localized: "How to add an iOS app"),
            "step1": String(localized: "Get a decrypted IPA file of the app. Copies from the App Store are encrypted and can't run."),
            "step2": String(localized: "Click “Add IPA files…” above and choose it on the iPhone (or download it and click Install in Files)."),
            "step3": String(localized: "Click “Install new apps into APLite” and pick ESign on the iPhone: it signs APLite again with the apps inside and installs it."),
            "step4": String(localized: "Open APLite again: the apps are in the app menu. Not every app works inside APLite."),
            "webNote": String(localized: "App Store apps can't open here: use their websites."),
            "open": String(localized: "Open"), "focus": String(localized: "Show"),
            "pin": String(localized: "Pin"), "unpin": String(localized: "Unpin"),
            "delete": String(localized: "Delete"), "remove": String(localized: "Remove from APLite"),
            "keep": String(localized: "Keep"), "confirm": String(localized: "Click again"),
            "export": String(localized: "Install new apps into APLite"),
            "reinstall": String(localized: "Reinstall APLite (remove selected apps)"),
            "preparing": String(localized: "Preparing the install file…"),
            "advanced": String(localized: "Certificate (advanced)…"),
            "caches": String(localized: "Apps' caches"),
            "report": String(localized: "Report"),
            "known": String(localized: "Apps others have tried"),
            "clearCaches": String(localized: "Clear when APLite reopens"), "cancelClear": String(localized: "Don't clear"),
        ] : [
            "title": String(localized: "Settings"),
            "display": String(localized: "Display"), "brightness": String(localized: "Brightness"),
            "resolution": String(localized: "Resolution"), "auto": String(localized: "Automatic"),
            "overscan": String(localized: "Fit the picture inside a TV's edges (overscan)"),
            "wallpaper": String(localized: "Wallpaper"), "photo": String(localized: "Choose a photo on the iPhone…"),
            "photoFiles": String(localized: "Choose a picture from Files…"), "blur": String(localized: "Blur"),
            "nightFilter": String(localized: "Night filter"), "off": String(localized: "Off"),
            "schedule": String(localized: "21:00–7:00"), "always": String(localized: "Always"),
            "desktop": String(localized: "Desktop"),
            "autoHide": String(localized: "Auto-hide the dock"),
            "performanceMode": String(localized: "Performance mode (smoother AirPlay / Wi-Fi)"),
            "reduceMotion": String(localized: "Reduce motion (follows iPhone setting)"),
            "dock": String(localized: "Dock"),
            "dockSize": String(localized: "Dock size"), "dockIconSize": String(localized: "Icon size"),
            "dockSpacing": String(localized: "Icon spacing"), "dockOpacity": String(localized: "Glass opacity"),
            "dockMagnify": String(localized: "Magnify icons on hover"),
            "dockTheme": String(localized: "Dock appearance"), "dark": String(localized: "Dark"),
            "light": String(localized: "Light"), "autoTheme": String(localized: "Automatic"),
            "iconSize": String(localized: "Desktop icon size"), "small": String(localized: "Small"),
            "medium": String(localized: "Medium"), "large": String(localized: "Large"), "widgets": String(localized: "Clock and calendar widgets"),
            "dnd": String(localized: "Do not disturb (no notification pop-ups)"),
            "workspaces": String(localized: "Workspaces (4 desktops)"),
            "zoom": String(localized: "Text size of pages"),
            "tvMode": String(localized: "TV mode"), "apply": String(localized: "Turn on"),
            "browser": String(localized: "Browser"), "browserTitle": String(localized: "Browser settings"),
            "bookmarksBar": String(localized: "Show the bookmarks bar"), "adsHeader": String(localized: "Ads and trackers"),
            "browserLink": String(localized: "Ads and trackers, dark pages, bookmarks bar"),
            "openBrowser": String(localized: "Open"),
            "blockAds": String(localized: "Block ads and trackers"),
            "darkPages": String(localized: "Dark pages"),
            "builtInList": String(localized: "APLite's list of ad and tracking servers"),
            "blockedSites": String(localized: "Always block"), "allowedSites": String(localized: "Never block on"),
            "sitePlaceholder": String(localized: "example.com"),
            "power": String(localized: "Power"),
            "sleep": String(localized: "Sleep"), "wake": String(localized: "Wake"),
            "shutdown": String(localized: "Shut down APLite"),
            "powerNote": String(localized: "These control the APLite environment. iOS does not let an app switch the iPhone or iPad off or on."),
            "systemSettings": String(localized: "Open system settings on iPhone"),
            "sound": String(localized: "Sound"),
            "audioNote": String(localized: "Sound from guest apps, web pages and files follows the iPhone's audio route. Use the Sound button on the iPhone screen to pick AirPods, the speaker or the display."),
            "audioDiagnostics": String(localized: "Copy audio diagnostics"),
            "help": String(localized: "Help"), "guide": String(localized: "Show the guide on the iPhone"),
            "autoUpdateLabel": String(localized: "Check for new versions on GitHub"), "checkNow": String(localized: "Check now"),
            "downloadUpdate": String(localized: "Update to"),
            "guideNote": String(localized: "Apps, trackpad and keyboard."),
            "windows": String(localized: "Windows"), "maxWindows": String(localized: "Open at most"),
            "noLimit": String(localized: "No limit"),
            "reopenApps": String(localized: "Reopen iOS apps from last time"),
            "hotCorners": String(localized: "Hot corners"),
            "security": String(localized: "Lock and screen saver"), "lockToggle": String(localized: "Lock the desktop when I come back"),
            "saverLabel": String(localized: "Screen saver after"), "never": String(localized: "Never"), "min": String(localized: "min"),
            "saverStyle": String(localized: "Screen saver style"),
            "saverClock": String(localized: "Drifting clock"),
            "saverGradient": String(localized: "APLite gradient"),
            "saverWallpaper": String(localized: "Blurred wallpaper"),
            "saverMotion": String(localized: "Let the clock drift (avoids burn-in)"),
            "saverFade": String(localized: "Fade duration"),
            "lockNow": String(localized: "Lock now"),
            "typing": String(localized: "Typing"), "replacements": String(localized: "Text replacement"),
            "short": String(localized: "Type"), "phrase": String(localized: "To get"), "add": String(localized: "Add"),
            "direction": String(localized: "Scroll direction"), "natural": String(localized: "Natural (Mac)"),
            "traditional": String(localized: "Traditional"),
            "trackpad": String(localized: "Trackpad on the iPhone"), "pointer": String(localized: "Pointer speed"),
            "scroll": String(localized: "Scrolling speed"), "reset": String(localized: "Reset to defaults"),
            "accessibility": String(localized: "Accessibility"),
            "mouseModeButton": String(localized: "Always show the mouse mode button"),
            "virtualKeyboard": String(localized: "On-screen keyboard (appears when you click a field)"),
            "keyboardAlwaysVisible": String(localized: "Keep the keyboard visible when no field is focused"),
            "keyboardSettings": String(localized: "All keys & keyboard settings on iPhone"),
            "facebookEnhancements": String(localized: "Clean Facebook layout (hide side rails and ads)"),
            "about": String(localized: "Version"),
            "cookies": String(localized: "Accounts & cookies"),
            "cookieNote": String(localized: "Logins in web windows are saved to APLite's local vault automatically, including on the external display. iOS does not let APLite read Safari's cookie jar: to bring an account over, copy its Cookie header or import a cookies.txt file below. Values stay on this device."),
            "cookieDomain": String(localized: "Domain, e.g. example.com"),
            "cookiePaste": String(localized: "Paste cookies: name=value; name2=value2"),
            "cookieImport": String(localized: "Import pasted cookies"),
            "cookieFile": String(localized: "Import cookies.txt…"),
            "cookieClear": String(localized: "Clear"),
            "cookieSaveCurrent": String(localized: "Save login cookies"),
            "cookieSaveAll": String(localized: "Save all accounts"),
            "cookieVault": String(localized: "Saved login cookies"),
            "cookieVaultEmpty": String(localized: "No saved logins yet."),
            "cookieVaultRemove": String(localized: "Forget"),
            "cookieExport": String(localized: "Export saved…"),
            "aboutTitle": String(localized: "About APLite"),
            "liveTitle": String(localized: "Live configuration"),
            "attribution": String(localized: "APLite is an independently developed project based on the original iDesk project by itshieuk.\n\nOriginal project:\nhttps://github.com/itshieuk/iDesk\n\nAPLite introduces independent design changes, improvements, modifications and additional features while acknowledging the original project’s author and contributors.\n\nAPLite is not an official release or endorsement of the original iDesk project."),
            "upstream": String(localized: "Original project"), "apliteRepo": String(localized: "APLite repository"),
        ]
        let initial = json(state(page)), t = json(strings)
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <title>\(strings["title"] ?? "")</title>
        <style>
        :root { color-scheme: dark; --accent: #38bdf8; --accent2: #0ea5a4; }
        * { box-sizing: border-box; }
        body { margin: 0; padding: 26px 30px 40px; min-height: 100vh;
               background: radial-gradient(1000px 500px at 12% -10%, rgba(56,189,248,.13), transparent 70%),
                           radial-gradient(800px 500px at 100% 0%, rgba(14,165,164,.10), transparent 65%), #111318;
               color: #f2f5f8; font: 15px -apple-system, sans-serif;
               user-select: none; -webkit-user-select: none; }
        h1 { font-size: 24px; margin: 0 0 4px; }
        h2 { font-size: 12px; text-transform: uppercase; letter-spacing: .10em; color: var(--accent);
             margin: 28px 0 10px; font-weight: 700; }
        .sub, .note { color: #999; font-size: 13px; }
        .card { background: linear-gradient(180deg, rgba(255,255,255,.055), rgba(255,255,255,.018)), #1c2026;
                border: 1px solid rgba(255,255,255,.075); border-radius: 16px; padding: 4px 16px;
                box-shadow: 0 12px 30px rgba(0,0,0,.24); }
        .row { display: flex; align-items: center; gap: 12px; min-height: 52px; border-top: 1px solid #2f2f33; }
        .row:first-child { border-top: 0; }
        .row .label { flex: 1; }
        button { background: #34343a; color: #eee; border: 0; border-radius: 8px; padding: 8px 13px; font: inherit;
                 font-size: 14px; cursor: pointer; }
        button:hover { background: #45454c; }
        button.primary { background: linear-gradient(135deg, var(--accent), var(--accent2)); color: #04212b; font-weight: 600; }
        button.primary:hover { filter: brightness(1.12); }
        button.danger { color: #ff8a80; }
        button:disabled { opacity: .45; }
        .round { width: 34px; height: 34px; padding: 0; border-radius: 17px; font-size: 18px; }
        .value { min-width: 56px; text-align: center; font-variant-numeric: tabular-nums; color: #ccc; }
        .switch { width: 46px; height: 28px; border-radius: 14px; background: #48484e; position: relative; flex: none; }
        .switch::after { content: ''; position: absolute; top: 3px; left: 3px; width: 22px; height: 22px; border-radius: 11px;
                         background: #fff; transition: left .15s; }
        .switch.on { background: #30d158; } .switch.on::after { left: 21px; }
        .seg { display: flex; gap: 6px; flex-wrap: wrap; }
        .seg button.on { background: linear-gradient(135deg, var(--accent), var(--accent2)); color: #04212b; }
        .walls { display: flex; gap: 10px; flex-wrap: wrap; padding: 12px 0; }
        .wall { display: flex; align-items: flex-end; justify-content: flex-end; padding: 4px; font-size: 14px; width: 110px; height: 62px; border-radius: 9px; border: 2px solid transparent; background-size: cover;
                background-position: center; cursor: pointer; }
        .wall.on { border-color: var(--accent); box-shadow: 0 0 0 3px rgba(56,189,248,.15); }
        .wall:hover { border-color: #8b97a5; } .wall.on:hover { border-color: var(--accent); }
        .app { display: flex; align-items: center; gap: 14px; padding: 12px 0; border-top: 1px solid #2f2f33; }
        .app:first-child { border-top: 0; }
        .app img, .app .noicon { width: 46px; height: 46px; border-radius: 11px; flex: none; background: #2a8; }
        .app .info { flex: 1; min-width: 0; }
        .app .name { font-weight: 600; }
        .app .status { font-size: 12px; margin-top: 3px; }
        .good { color: #30d158; } .warn { color: #ff9f0a; } .bad { color: #ff6961; } .muted { color: #8e8e93; }
        .actions { display: flex; gap: 6px; flex-wrap: wrap; justify-content: flex-end; }
        .head { display: flex; align-items: flex-end; gap: 12px; }
        .head .grow { flex: 1; }
        .bar { height: 8px; border-radius: 4px; background: #3a3a40; overflow: hidden; margin-top: 8px; }
        .bar div { height: 100%; background: linear-gradient(90deg, var(--accent), var(--accent2)); }
        a { color: #8ab4ff; text-decoration: none; } a:hover { text-decoration: underline; }
        input, textarea { background: #262b32; color: #f2f5f8; border: 1px solid rgba(255,255,255,.08);
                border-radius: 9px; padding: 8px 12px; font: inherit; font-size: 14px; width: 220px;
                -webkit-user-select: text; user-select: text; }
        textarea { width: 100%; resize: vertical; line-height: 1.45; }
        .wall { transition: transform .18s ease, border-color .18s ease; }
        .wall:hover { transform: translateY(-2px); }
        button { transition: background .18s ease, filter .18s ease, transform .12s ease; }
        button:active { transform: scale(.97); }
        .seg button.on, button.on { background: linear-gradient(135deg, var(--accent), var(--accent2)); color: #04212b; }
        .day { color: #8e8e93; font-size: 12px; font-weight: 600; text-transform: uppercase; padding: 14px 0 4px; }
        .entry { display: flex; align-items: center; gap: 12px; min-height: 38px; border-top: 1px solid #2f2f33; }
        .entry a { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .entry .time { color: #8e8e93; font-size: 12px; width: 64px; flex: none; font-variant-numeric: tabular-nums; }
        .entry .muted { font-size: 12px; max-width: 180px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .entry .x { padding: 2px 9px; background: transparent; color: #8e8e93; font-size: 16px; }
        .entry .x:hover { background: #3a3a40; color: #eee; }
        </style></head><body><div id="root"></div>
        <script>
        const T = \(t);
        function send(action, value) {
          window.webkit.messageHandlers.\(messageName).postMessage({ action: action, value: value === undefined ? '' : String(value) });
        }
        function esc(s) { return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
        // Destructive buttons ask for a second click (a page cannot show a dialog on the desktop).
        function twice(button, action, value) {
          if (!button.dataset.armed) {
            button.dataset.armed = '1'; const text = button.textContent; button.textContent = T.confirm;
            setTimeout(() => { delete button.dataset.armed; button.textContent = text; }, 3000);
            return;
          }
          send(action, value);
        }
        const PAGE = '\(page.rawValue)';
        \(page == .apps ? appsScript : page == .history ? historyScript : settingsScript)
        render(\(initial));
        </script></body></html>
        """
    }

    private static let settingsScript = #"""
    function toggle(key, on, label) {
      return `<div class="row" onclick="send('${key}')"><div class="label">${esc(label)}</div><div class="switch ${on ? 'on' : ''}"></div></div>`;
    }
    function stepper(key, label, value, step) {
      return `<div class="row"><div class="label">${esc(label)}</div>
        <button class="round" onclick="send('${key}', -${step})">−</button><div class="value">${esc(value)}</div>
        <button class="round" onclick="send('${key}', ${step})">+</button></div>`;
    }
    function browserPage(s) {
      const siteList = (id, key, sites, label) => `<div class="card"><div class="row"><div class="label"><b>${esc(label)}</b></div></div>`
        + sites.map(x => `<div class="row"><div class="label">${esc(x)}</div><button onclick="send('unlistSite', ${JSON.stringify(x).replace(/"/g, '&quot;')})">×</button></div>`).join('')
        + `<div class="row"><input id="${id}" placeholder="${esc(T.sitePlaceholder)}" autocapitalize="off" autocorrect="off" style="flex:1;margin-right:8px"`
        + ` onkeydown="if (event.key === 'Enter' && this.value) send('${key}', this.value)">`
        + `<button onclick="const v = document.getElementById('${id}').value; if (v) send('${key}', v)">${esc(T.add)}</button></div></div>`;
      return `<h1>${esc(T.browserTitle)}</h1>`
        + `<div class="card">` + toggle('bookmarksBar', s.bookmarksBar, T.bookmarksBar) + `</div>`
        + `<h2>${esc(T.adsHeader)}</h2><div class="card">` + toggle('blockAds', s.blockAds, T.blockAds)
        + `<div style="${s.blockAds ? '' : 'opacity:.45;pointer-events:none'}">` + toggle('builtInList', s.builtInList, T.builtInList + ' (' + s.builtInCount + ')') + `</div>`
        + `</div>`
        + `<div style="${s.blockAds ? '' : 'opacity:.45;pointer-events:none'}">`
        + siteList('bs', 'blockSite', s.blockedSites, T.blockedSites) + siteList('as', 'allowSite', s.allowedSites, T.allowedSites)
        + `</div>`
        + `<div class="card">` + toggle('darkPages', s.darkPages, T.darkPages)
        + toggle('facebookEnhancements', s.facebookEnhancements, T.facebookEnhancements) + `</div>`;
    }
    function render(s) {
      const key = JSON.stringify(s); if (key === window.__shown) return; window.__shown = key;
      if (PAGE === 'browser') { document.getElementById('root').innerHTML = browserPage(s); return; }
      let h = `<h1>${esc(T.title)}</h1>`;
      if (s.connected) {
        h += `<h2>${esc(T.display)}</h2><div class="card">${stepper('brightness', T.brightness, s.brightness + '%', 0.1)}`;
        if (s.resolutions.length > 1) {
          h += `<div class="row"><div class="label">${esc(T.resolution)}</div><div class="seg">`
            + `<button class="${s.resolution === '' ? 'on' : ''}" onclick="send('resolution', '')">${esc(T.auto)}</button>`;
          s.resolutions.forEach(r => {
            h += `<button class="${s.resolution === r ? 'on' : ''}" onclick="send('resolution', '${r}')">${r.replace('x', '×')}</button>`;
          });
          h += `</div></div>`;
        }
        h += toggle('overscan', s.overscan, T.overscan) + `</div>`;
      }
      h += `<div class="card" style="margin-top:${s.connected ? 12 : 26}px"><div class="row"><div class="label">${esc(T.zoom)}</div><div class="seg">`
        + s.zooms.map(z => `<button class="${s.zoom === z ? 'on' : ''}" onclick="send('zoom', ${z})">${z}%</button>`).join('')
        + `</div></div></div>`
        + `<div class="card"><div class="row"><div class="label">${esc(T.tvMode)}</div><button onclick="send('tvMode')">${esc(T.apply)}</button></div></div>`;
      h += `<h2>${esc(T.wallpaper)}</h2><div class="card"><div class="walls">`;
      s.wallpapers.forEach((c, i) => {
        h += `<div class="wall ${s.wallpaper === i ? 'on' : ''}" style="background-image:linear-gradient(135deg, ${c.join(',')})" onclick="send('wallpaper', ${i})"></div>`;
      });
      h += `<div class="wall ${s.wallpaper === -2 ? 'on' : ''}" style="background-image:linear-gradient(135deg, ${s.dynamic.join(',')})" onclick="send('wallpaper', -2)">🕒</div>`;
      s.photos.forEach(p => {
        const art = p[1] === 'MeadowWallpaper' ? '🌿' : '🌊';
        const thumb = s.photoThumbs[String(p[0])];
        const bg = thumb ? `url(${thumb})`
          : p[1] === 'MeadowWallpaper'
            ? 'linear-gradient(135deg, #2c5a30, #7a9e46, #e3c46b)'
            : 'linear-gradient(135deg, #0b2f52, #157a9c, #e8b46a)';
        h += `<div class="wall ${s.wallpaper === p[0] ? 'on' : ''}" style="background-image:${bg}" onclick="send('wallpaper', ${p[0]})" title="${esc(p[2])}">${art}</div>`;
      });
      if (s.custom) h += `<div class="wall ${s.wallpaper === -1 ? 'on' : ''}" style="background-image:url(${s.custom})" onclick="send('wallpaper', -1)"></div>`;
      h += `</div>` + stepper('wallpaperBlur', T.blur, s.wallpaperBlur + '%', 2)
        + `<div class="row"><div class="label"></div><button onclick="send('photo')">${esc(T.photo)}</button>`
        + `<button onclick="send('photoFiles')">${esc(T.photoFiles)}</button></div></div>`;
      h += `<div class="card"><div class="row"><div class="label">${esc(T.nightFilter)}</div><div class="seg">`
        + [[0, T.off], [1, T.schedule], [2, T.always]].map(([n, l]) =>
            `<button class="${s.night === n ? 'on' : ''}" onclick="send('night', ${n})">${esc(l)}</button>`).join('')
        + `</div></div></div>`;
      h += `<h2>${esc(T.desktop)}</h2><div class="card">` + toggle('autoHide', s.autoHide, T.autoHide)
        + toggle('performanceMode', s.performance, T.performanceMode)
        + toggle('reduceMotion', s.reduceMotion, T.reduceMotion)
        + toggle('widgets', s.widgets, T.widgets) + toggle('dnd', s.dnd, T.dnd)
        + `<div class="row"><div class="label">${esc(T.iconSize)}</div><div class="seg">`
        + [[0, T.small], [1, T.medium], [2, T.large]].map(([n, l]) =>
            `<button class="${s.iconSize === n ? 'on' : ''}" onclick="send('iconSize', ${n})">${esc(l)}</button>`).join('')
        + `</div></div>` + toggle('workspaces', s.workspaces, T.workspaces) + `</div>`
        + `<div class="card">` + toggle('hotCorners', s.hotCorners, T.hotCorners) + `</div>`;
      h += `<h2>${esc(T.dock)}</h2><div class="card">`
        + stepper('dockScale', T.dockSize, Number(s.dockScale).toFixed(2) + '×', 0.1)
        + stepper('dockIcon', T.dockIconSize, Math.round(s.dockIcon * 100) + '%', 0.1)
        + stepper('dockSpacing', T.dockSpacing, Math.round(s.dockSpacing) + ' px', 2)
        + stepper('dockOpacity', T.dockOpacity, Math.round(s.dockOpacity * 100) + '%', 0.1)
        + toggle('dockMagnify', s.dockMagnify, T.dockMagnify)
        + `<div class="row"><div class="label">${esc(T.dockTheme)}</div><div class="seg">`
        + [[0, T.dark], [1, T.light], [2, T.autoTheme]].map(([n, l]) =>
            `<button class="${s.dockAppearance === n ? 'on' : ''}" onclick="send('dockAppearance', ${n})">${esc(l)}</button>`).join('')
        + `</div></div></div>`;
      h += `<h2>${esc(T.security)}</h2><div class="card">` + toggle('lock', s.lock, T.lockToggle)
        + `<div class="row"><div class="label">${esc(T.saverLabel)}</div><div class="seg">`
        + [0, 1, 2, 5, 10, 15, 30, 60].map(n => `<button class="${s.saver === n ? 'on' : ''}" onclick="send('saver', ${n})">${n ? n + ' ' + esc(T.min) : esc(T.never)}</button>`).join('')
        + `</div></div>`
        + `<div class="row"><div class="label">${esc(T.saverStyle)}</div><div class="seg">`
        + [[0, T.saverClock], [1, T.saverGradient], [2, T.saverWallpaper]].map(([n, l]) =>
            `<button class="${s.saverStyle === n ? 'on' : ''}" onclick="send('saverStyle', ${n})">${esc(l)}</button>`).join('')
        + `</div></div>`
        + toggle('saverMotion', s.saverMotion, T.saverMotion)
        + stepper('saverFade', T.saverFade, Number(s.saverFade).toFixed(1) + ' s', 0.2)
        + `<div class="row"><div class="label"></div><button onclick="send('lockNow')">🔒 ${esc(T.lockNow)}</button></div></div>`;
      h += `<h2>${esc(T.typing)}</h2><div class="card">` + s.replacements.map(([a, b]) =>
          `<div class="row"><div class="label"><b>${esc(a)}</b> → ${esc(b)}</div><button onclick="send('removeReplacement', '${esc(a).replace(/'/g, "\\'")}')">×</button></div>`).join('')
        + `<div class="row"><input id="rs" placeholder="${esc(T.short)}" style="width:90px"> <input id="rp" placeholder="${esc(T.phrase)}" style="flex:1;margin:0 8px">`
        + `<button onclick="const a = document.getElementById('rs').value, b = document.getElementById('rp').value; if (a && b) send('addReplacement', a + '\u0001' + b)">${esc(T.add)}</button></div>`
         + toggle('virtualKeyboard', s.virtualKeyboard, T.virtualKeyboard)
         + toggle('keyboardAlwaysVisible', s.keyboardAlwaysVisible, T.keyboardAlwaysVisible)
         + `<div class="row"><div class="label"></div><button onclick="send('systemSettings')">${esc(T.keyboardSettings)}</button></div></div>`;
      h += `<h2>${esc(T.browser)}</h2><div class="card"><div class="row"><div class="label">${esc(T.browserLink)}</div>`
        + `<button onclick="send('browserSettings')">${esc(T.openBrowser)}</button></div></div>`;
      h += `<h2>${esc(T.windows)}</h2><div class="card"><div class="row"><div class="label">${esc(T.maxWindows)}</div><div class="seg">`;
      [-1, 2, 3, 4, 6, 8, 0].forEach(n => {
        const label = n < 0 ? T.auto : n ? n : T.noLimit;
        h += `<button class="${s.maxWindows === n ? 'on' : ''}" onclick="send('maxWindows', ${n})">${esc(label)}</button>`;
      });
      h += `</div></div>` + toggle('reopenApps', s.reopenApps, T.reopenApps) + `</div>`;
      h += `<h2>${esc(T.trackpad)}</h2><div class="card">` + stepper('pointer', T.pointer, s.pointer, 0.2)
        + stepper('scroll', T.scroll, s.scroll, 0.4)
        + `<div class="row"><div class="label">${esc(T.direction)}</div><div class="seg">`
        + `<button class="${s.natural ? 'on' : ''}" onclick="send('natural', 1)">${esc(T.natural)}</button>`
        + `<button class="${s.natural ? '' : 'on'}" onclick="send('natural', 0)">${esc(T.traditional)}</button></div></div>`
        + `<div class="row"><div class="label"></div><button onclick="send('resetSpeeds')">${esc(T.reset)}</button></div></div>`;
      h += `<h2>${esc(T.accessibility)}</h2><div class="card">` + toggle('mouseModeButton', s.mouseModeButton, T.mouseModeButton)
        + `</div>`;
      h += `<h2>${esc(T.power)}</h2><div class="card"><div class="row"><div class="label">${esc(T.power)}</div><div class="note">${esc(s.powerState)}</div></div>`
        + `<div class="row"><div class="label note" style="white-space:normal;padding:10px 0;line-height:1.5">${esc(T.powerNote)}</div></div>`
        + `<div class="row"><div class="label"></div><button onclick="send('sleep')">${esc(T.sleep)}</button>`
        + `<button onclick="send('wake')">${esc(T.wake)}</button>`
        + `<button class="danger" onclick="send('shutdown')">${esc(T.shutdown)}</button></div></div>`;
      h += `<h2>${esc(T.sound)}</h2><div class="card"><div class="row"><div class="label note" style="white-space:normal;padding:10px 0;line-height:1.5">${esc(T.audioNote)}</div></div>`
        + `<div class="row"><div class="label"></div><button onclick="send('audioDiagnostics')">${esc(T.audioDiagnostics)}</button></div></div>`;
      h += `<h2>${esc(T.help)}</h2><div class="card"><div class="row"><div class="label">${esc(T.guideNote)}</div>`
        + `<button onclick="send('guide')">${esc(T.guide)}</button></div></div>`;
      h += `<div class="card">` + toggle('autoUpdate', s.autoUpdate, T.autoUpdateLabel)
        + `<div class="row"><div class="label">${esc(s.updateResult)}</div>`
        + (s.update ? `<button class="primary" onclick="send('downloadUpdate')">${esc(T.downloadUpdate)} ${esc(s.update)}</button>`
                    : `<button onclick="send('checkUpdate')">${esc(T.checkNow)}</button>`)
        + `</div></div>`;
      h += `<h2>${esc(T.cookies)}</h2><div class="card">`
        + `<div class="row"><div class="label note" style="white-space:normal;padding:10px 0;line-height:1.5">${esc(T.cookieNote)}</div></div>`
        + `<div class="row"><input id="cookieDomain" placeholder="${esc(T.cookieDomain)}" autocapitalize="off" autocorrect="off" style="flex:1">`
        + `<button onclick="const d=document.getElementById('cookieDomain').value.trim(); if(d) send('cookieClear', d)">${esc(T.cookieClear)}</button></div>`
        + `<div class="row"><textarea id="cookieValue" rows="3" placeholder="${esc(T.cookiePaste)}" autocapitalize="off" autocorrect="off"></textarea></div>`
        + `<div class="row"><div class="label"></div><button class="primary" onclick="const d=document.getElementById('cookieDomain').value.trim(), v=document.getElementById('cookieValue').value.trim(); if(d&&v) send('cookieAdd', d+'\u0001'+v)">${esc(T.cookieImport)}</button>`
        + `<button onclick="send('cookieFile')">${esc(T.cookieFile)}</button>`
        + `<button onclick="const d=document.getElementById('cookieDomain').value.trim(); if(d) send('cookieSaveCurrent', d)">${esc(T.cookieSaveCurrent)}</button>`
         + `<button onclick="send('cookieSaveAll')">${esc(T.cookieSaveAll)}</button></div>`
        + `<div class="row"><div class="label"><b>${esc(T.cookieVault)}</b></div><button onclick="send('cookieExport')">${esc(T.cookieExport)}</button></div>`
        + (s.savedCookies.length ? s.savedCookies.map(x =>
            `<div class="row"><div class="label">${esc(x.domain)} <span class="note">(${x.count})</span></div>`
            + `<button onclick="send('cookieVaultRemove', ${JSON.stringify(x.domain).replace(/"/g, '&quot;')})">${esc(T.cookieVaultRemove)}</button></div>`).join('')
          : `<div class="row"><div class="label note">${esc(T.cookieVaultEmpty)}</div></div>`)
        + `</div>`;
      h += `<h2>${esc(T.aboutTitle)}</h2><div class="card">`
        + `<div class="row"><div class="label"><b>APLite</b> · AirPlayLite<br><span class="note">${esc(T.about)} ${esc(s.version)}</span></div></div>`
        + `<div class="row"><div class="label note" style="white-space:pre-line;padding:10px 0;line-height:1.5">${esc(T.attribution)}</div></div>`
        + (s.liveNotice ? `<div class="row"><div class="label note" style="white-space:normal;padding:10px 0">${esc(T.liveTitle)}: ${esc(s.liveNotice)}</div></div>` : ``)
        + `<div class="row"><div class="label"></div><button onclick="send('upstream')">${esc(T.upstream)}</button>`
        + `<button onclick="send('aplite')">${esc(T.apliteRepo)}</button>`
        + `<button class="primary" onclick="send('systemSettings')">${esc(T.systemSettings)}</button></div></div>`;
      document.getElementById('root').innerHTML = h;
    }
    """#

    private static let historyScript = #"""
    let state = null;
    function render(s) {
      const key = JSON.stringify(s); if (key === window.__shown) return; window.__shown = key;
      state = s;
      const root = document.getElementById('root');
      if (!document.getElementById('list')) {
        // Built once, so the search field keeps what is typed in it while the lists update.
        root.innerHTML = `<h1>${esc(T.title)}</h1><h2>${esc(T.bookmarks)}</h2><div class="card" id="marks"></div>
          <div class="head" style="margin-top:26px"><div class="grow"><h2 style="margin:0">${esc(T.history)}</h2></div>
          <input id="q" placeholder="${esc(T.search)}" oninput="drawHistory()">
          <button class="danger" onclick="twice(this, 'clear')">${esc(T.clear)}</button></div>
          <div class="card" id="list" style="margin-top:8px"></div>`;
      }
      let m = '';
      if (!s.bookmarks.length) m = `<p class="note" style="padding:10px 0">${esc(T.noBookmarks)}</p>`;
      s.bookmarks.forEach(b => {
        m += `<div class="app"><div class="info"><a class="name" href="${esc(b.url)}">${esc(b.title)}</a>
          <div class="status muted">${esc(b.host)}</div></div><div class="actions">
          <button ${b.desktop ? 'class="on"' : ''} onclick="send('desktop', ${JSON.stringify(b.url).replace(/"/g, '&quot;')})">${esc(b.desktop ? T.onDesktop : T.toDesktop)}</button>
          <button class="danger" onclick="send('unbookmark', ${JSON.stringify(b.url).replace(/"/g, '&quot;')})">${esc(T.remove)}</button></div></div>`;
      });
      document.getElementById('marks').innerHTML = m;
      drawHistory();
    }
    function drawHistory() {
      if (!state) return;
      const q = (document.getElementById('q').value || '').toLowerCase();
      let h = '', day = '';
      const items = state.history.filter(e => !q || e.title.toLowerCase().includes(q) || e.url.toLowerCase().includes(q));
      if (!items.length) h = `<p class="note" style="padding:10px 0">${esc(T.noHistory)}</p>`;
      items.forEach(e => {
        if (e.day !== day) { day = e.day; h += `<div class="day">${esc(day)}</div>`; }
        const arg = JSON.stringify(e.id + ' ' + e.url).replace(/"/g, '&quot;');
        h += `<div class="entry"><span class="time">${esc(e.time)}</span><a href="${esc(e.url)}">${esc(e.title)}</a>
          <span class="muted">${esc(e.host)}</span><button class="x" onclick="send('forget', ${arg})">×</button></div>`;
      });
      document.getElementById('list').innerHTML = h;
    }
    """#

    private static let appsScript = #"""
    function render(s) {
      const key = JSON.stringify(s); if (key === window.__shown) return; window.__shown = key;
      let h = `<div class="head"><div class="grow"><h1>${esc(T.title)}</h1></div>`;
      h += `<button class="primary" ${s.adding ? 'disabled' : ''} onclick="send('add')">${esc(s.adding || T.add)}</button></div>`;
      if (s.export !== null) {
        h += `<h2>${esc(T.preparing)}</h2><div class="card" style="padding:14px 16px"><div class="bar"><div style="width:${s.export}%"></div></div></div>`;
      } else if (s.canExport) {
        h += `<h2></h2><div class="card" style="padding:14px 16px"><button class="primary" onclick="send('export')">${esc(s.reinstallOnly ? T.reinstall : T.export)}</button>
          </div>`;
      }
      h += `<h2>${esc(s.total)}</h2><div class="card">`;
      if (!s.apps.length) {
        h += `<p class="note" style="padding:10px 0 0">${esc(T.empty)}</p><p style="margin:14px 0 6px;font-weight:600">${esc(T.howTo)}</p><ol class="note" style="line-height:1.6;padding-left:20px">`
          + [T.step1, T.step2, T.step3, T.step4].map(x => `<li>${esc(x)}</li>`).join('') + `</ol><p class="note" style="padding-bottom:10px">${esc(T.webNote)}</p>`;
      }
      s.apps.forEach(a => {
        const id = esc(a.id).replace(/'/g, '');
        h += `<div class="app">${a.icon ? `<img src="${a.icon}">` : '<div class="noicon"></div>'}
          <div class="info"><div class="name">${esc(a.name)}</div><div class="status ${a.tone}">${esc(a.status)}</div>
          ${a.compat ? `<div class="status ${a.compatTone}">${esc(a.compat)}</div>` : ''}</div>
          <div class="actions"><button class="primary" onclick="send('open','${id}')">${esc(a.open ? T.focus : T.open)}</button>
          <button onclick="send('pin','${id}')">${esc(a.pinned ? T.unpin : T.pin)}</button>
          <button onclick="send('report','${id}')">${esc(T.report)}</button>
          <button class="danger" onclick="twice(this,'${a.removal}','${id}')">${esc(T[a.removal])}</button></div></div>`;
      });
      h += `</div>`;
      if (s.known.length) {
        h += `<h2>${esc(T.known)}</h2><div class="card">` + s.known.map(k =>
          `<div class="app"><div class="info"><div class="name">${esc(k.name)}</div><div class="status ${k.tone}">${esc(k.note)}</div></div></div>`).join('')
          + `</div>`;
      }
      if (s.caches) {
        h += `<div class="card"><div class="row"><div class="label">${esc(T.caches)} · <b>${esc(s.caches)}</b></div>`
          + `<button ${s.cleanPending ? 'class="on"' : ''} onclick="send('clearCaches')">${esc(s.cleanPending ? T.cancelClear : T.clearCaches)}</button></div></div>`;
      }
      h += `<p><button onclick="send('advanced')">${esc(T.advanced)}</button></p>`;
      document.getElementById('root').innerHTML = h;
    }
    """#
}

/// Buttons on the Settings and Apps pages. Only APLite's own pages may use it.
final class PageBridge: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let url = message.webView?.url, url.scheme == "idesk",
              let page = DesktopPage(url), page != .files,
              let body = message.body as? [String: String], let action = body["action"] else { return }
        if page == .editor {
            if action == "save" { TextEditor.save(body["value"] ?? "", to: url) }
            if action == "saveAs", let webView = message.webView {
                TextEditor.saveAs(body["value"] ?? "", name: body["name"] ?? "", from: url, in: webView)
            }
            return
        }
        DesktopPages.handle(page, action: action, value: body["value"] ?? "")
    }
}
