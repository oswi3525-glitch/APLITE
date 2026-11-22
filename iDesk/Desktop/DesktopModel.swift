import UIKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import Combine
import Photos

// MARK: - Layout metrics (shared by drawing and hit testing)

enum Layout {
    static let titleBar: CGFloat = 34
    static let addressBar: CGFloat = 38            // web windows: back, forward, reload, address field
    static let bookmarksBar: CGFloat = 30          // under it, when there are bookmarks (Browsing.showsBookmarksBar)
    /// The band at the bottom of the screen that holds the floating dock. The dock itself is
    /// smaller and inset (see DesktopModel.dockRect); windows stop above this band.
    static let taskbar: CGFloat = 64
    static let resizeGrip: CGFloat = 22
    static let edgeGrab: CGFloat = 10           // how far outside a window's edge it can still be grabbed to resize
    static let minWindowSize = CGSize(width: 360, height: 260)

    // Title bar buttons (close / minimize / maximize), relative to the window frame.
    static func closeButton(in f: CGRect) -> CGRect { CGRect(x: f.minX + 12, y: f.minY + 9, width: 16, height: 16) }
    static func minimizeButton(in f: CGRect) -> CGRect { CGRect(x: f.minX + 34, y: f.minY + 9, width: 16, height: 16) }
    static func maximizeButton(in f: CGRect) -> CGRect { CGRect(x: f.minX + 56, y: f.minY + 9, width: 16, height: 16) }
    static func titleButtons(in f: CGRect) -> CGRect { CGRect(x: f.minX + 8, y: f.minY + 5, width: 70, height: 24) }

    // Tabs of a web window, in its title bar after the three buttons, then a "+" for a new tab.
    static let tabsX: CGFloat = 84
    static func tabRect(_ i: Int, count: Int, in f: CGRect) -> CGRect {
        let avail = f.width - tabsX - 44
        let w = max(44, min(200, avail / CGFloat(max(1, count))))
        return CGRect(x: f.minX + tabsX + CGFloat(i) * w, y: f.minY + 4, width: w - 4, height: titleBar - 6)
    }
    static func tabCloseRect(_ i: Int, count: Int, in f: CGRect) -> CGRect {
        let t = tabRect(i, count: count, in: f)
        return CGRect(x: t.maxX - 22, y: t.midY - 8, width: 16, height: 16)
    }
    static func newTabRect(count: Int, in f: CGRect) -> CGRect {
        let last = tabRect(count - 1, count: count, in: f)
        return CGRect(x: min(last.maxX + 6, f.maxX - 32), y: f.minY + 5, width: 24, height: 24)
    }

    // Address bar of a web window, below the title bar.
    static func addressRow(in f: CGRect) -> CGRect { CGRect(x: f.minX, y: f.minY + titleBar, width: f.width, height: addressBar) }
    static func backButton(in f: CGRect) -> CGRect { CGRect(x: f.minX + 8, y: f.minY + titleBar + 5, width: 28, height: 28) }
    static func forwardButton(in f: CGRect) -> CGRect { CGRect(x: f.minX + 40, y: f.minY + titleBar + 5, width: 28, height: 28) }
    static func reloadButton(in f: CGRect) -> CGRect { CGRect(x: f.minX + 72, y: f.minY + titleBar + 5, width: 28, height: 28) }
    static func addressField(in f: CGRect) -> CGRect {
        CGRect(x: f.minX + 108, y: f.minY + titleBar + 5, width: max(0, f.width - 180), height: 28)
    }
    static func bookmarkButton(in f: CGRect) -> CGRect { CGRect(x: f.maxX - 68, y: f.minY + titleBar + 5, width: 28, height: 28) }
    /// ⋯: the browser's menu (new tab, history, bookmarks bar, browser settings…).
    static func browserMenuButton(in f: CGRect) -> CGRect { CGRect(x: f.maxX - 36, y: f.minY + titleBar + 5, width: 28, height: 28) }

    // Bookmarks bar, under the address bar: one button per bookmark while they fit, then » for the others.
    static func bookmarksRow(in f: CGRect) -> CGRect {
        CGRect(x: f.minX, y: f.minY + titleBar + addressBar, width: f.width, height: bookmarksBar)
    }
    static let bookmarkFont = UIFont.systemFont(ofSize: 12)
    static func bookmarkItems(_ titles: [String], in f: CGRect) -> (items: [CGRect], more: CGRect?) {
        let y = f.minY + titleBar + addressBar + 3, h = bookmarksBar - 6
        var x = f.minX + 8, rects: [CGRect] = []
        let moreRect = CGRect(x: f.maxX - 34, y: y, width: 26, height: h)
        for (i, t) in titles.enumerated() {
            let text = (t as NSString).size(withAttributes: [.font: bookmarkFont]).width
            let w = min(180, ceil(text) + 42)   // icon, gap and padding (BookmarksBar.item)
            let limit = i == titles.count - 1 ? f.maxX - 8 : moreRect.minX - 4
            if x + w > limit { return (rects, moreRect) }
            rects.append(CGRect(x: x, y: y, width: w, height: h))
            x += w + 2
        }
        return (rects, nil)
    }

    // Taskbar / floating dock
    static let dockMargin: CGFloat = 12             // from the screen's left / right edges
    static let dockPadding: CGFloat = 7             // inside each glass pill
    static let dockGap: CGFloat = 5                 // between the three pills
    static let dockItemMin: CGFloat = 30
    static let dockItemMax: CGFloat = 52
    static let dockIconBase: CGFloat = 40
    static let dockControl: CGFloat = 38
    static let startWidth: CGFloat = 40
    static let navWidth: CGFloat = 36
    static let navGap: CGFloat = 4
    static let navCount: CGFloat = 4                // Spotlight, Recent apps, Home, Back
    static let workspaceCell: CGFloat = 18
    static let workspaceWidth: CGFloat = 4 * workspaceCell
    static let buttonHeight: CGFloat = 38
    static let trayWidth: CGFloat = 280
    static let showDesktopWidth: CGFloat = 12

    // App menu (grid)
    static let launcherColumns = 3
    static let launcherTile = CGSize(width: 104, height: 88)
    static let launcherGap: CGFloat = 6
    static let launcherPadding: CGFloat = 14
    static let launcherHeader: CGFloat = 76        // title + search field
    static let launcherSectionTitle: CGFloat = 24  // "Recent", "All apps"
    static let launcherFooter: CGFloat = 40        // "No iOS apps yet": the way to add them

    // Desktop icons
    /// A desktop icon's cell, at the size chosen in Settings (small, medium, large).
    static var iconCell: CGSize {
        let s = DesktopModel.iconScale(UserDefaults.standard.integer(forKey: DesktopModel.Keys.iconSize))
        return CGSize(width: (92 * s).rounded(), height: (92 * s).rounded())
    }
    static let iconGap: CGFloat = 6
    static let iconOrigin = CGPoint(x: 16, y: 16)

    // Recent apps
    static let recentsTile = CGSize(width: 300, height: 230)
    static let recentsGap: CGFloat = 24
    static let recentsTitle: CGFloat = 34          // icon + name above the thumbnail

    // Context menu
    static let menuWidth: CGFloat = 250
    static let menuItemHeight: CGFloat = 32
    static let menuSeparatorHeight: CGFloat = 9
    static let menuPadding: CGFloat = 6
}

struct Shortcut {
    let name: String
    let symbol: String
    let url: String
    let hue: Double
    /// Name of a bundled asset for APLite's own apps (nil for web pages and guest apps: those
    /// draw the site's or the guest app's real icon).
    var asset: String? = nil
    var app: GuestApp? = nil      // non-nil: an app installed from an IPA rather than a web page
    var file: String? = nil       // non-nil: a file in Files (its name in Downloads), put on the desktop
    var webApp = false            // a website installed as an app (WebApps): opens in its own window
}

enum CursorStyle {
    case arrow, pointer, text, grab, resizeH, resizeV, resizeNWSE, resizeNESW, crosshair
}

struct ResizeEdges: OptionSet {
    let rawValue: Int
    static let left = ResizeEdges(rawValue: 1)
    static let right = ResizeEdges(rawValue: 2)
    static let top = ResizeEdges(rawValue: 4)
    static let bottom = ResizeEdges(rawValue: 8)

    var cursorStyle: CursorStyle {
        if (contains(.left) && contains(.top)) || (contains(.right) && contains(.bottom)) { return .resizeNWSE }
        if (contains(.left) && contains(.bottom)) || (contains(.right) && contains(.top)) { return .resizeNESW }
        if contains(.left) || contains(.right) { return .resizeH }
        if contains(.top) || contains(.bottom) { return .resizeV }
        return .arrow
    }
}

// MARK: - Context menu

struct MenuItem {
    let title: String
    let symbol: String?
    let enabled: Bool
    let action: (() -> Void)?

    /// A title that is not translated (a page's name).
    init(verbatim title: String, _ symbol: String?, action: (() -> Void)?) {
        self.title = title
        self.symbol = symbol
        self.enabled = true
        self.action = action
    }

    init(_ title: String.LocalizationValue, _ symbol: String?, enabled: Bool = true, action: (() -> Void)?) {
        self.title = String(localized: title)
        self.symbol = symbol
        self.enabled = enabled
        self.action = action
    }

    static let separator = MenuItem("", nil, action: nil)
    var isSeparator: Bool { title.isEmpty && action == nil }
    var height: CGFloat { isSeparator ? Layout.menuSeparatorHeight : Layout.menuItemHeight }
}

struct ContextMenu {
    let items: [MenuItem]
    let frame: CGRect

    func itemRect(_ i: Int) -> CGRect {
        let y = items[..<i].reduce(frame.minY + Layout.menuPadding) { $0 + $1.height }
        return CGRect(x: frame.minX + Layout.menuPadding, y: y,
                      width: frame.width - Layout.menuPadding * 2, height: items[i].height)
    }
}

// MARK: - Windows

// MARK: - Notifications

/// A notification from an app running in iDesk, shown on the desktop.
struct DeskNotification: Identifiable {
    let id = UUID()
    let app: GuestApp?
    let title: String
    let body: String
    let date = Date()
}

// MARK: - Pointer (separate so moving it does not redraw the whole desktop)

final class CursorModel: ObservableObject {
    @Published var position: CGPoint = CGPoint(x: 200, y: 200)
    @Published var isPressed = false
    @Published var isHidden = false              // while a screenshot is taken
    /// A laptop's browser shows the desktop (RemoteDisplay) and draws its own pointer, which moves without delay.
    @Published var drawnByViewer = false
    @Published private(set) var style: CursorStyle = .arrow
    /// Bigger for a moment after a shake (ShakeDetector), to find the pointer on a large screen.
    @Published var magnify: CGFloat = 1

    func setStyle(_ s: CursorStyle) { if style != s { style = s } }
}

// MARK: - Desktop state

final class DesktopModel: ObservableObject {
    static let shared = DesktopModel()

    static let shortcuts: [Shortcut] = [
        Shortcut(name: String(localized: "Browser"), symbol: "globe", url: "https://www.google.com", hue: 0.60, asset: "BrowserIcon"),
        Shortcut(name: String(localized: "Files"), symbol: "folder.fill", url: DesktopPage.files.url.absoluteString, hue: 0.57, asset: "FilesIcon"),
        Shortcut(name: String(localized: "Settings"), symbol: "gearshape.fill", url: DesktopPage.settings.url.absoluteString, hue: 0.0, asset: "SettingsIcon"),
        Shortcut(name: String(localized: "Trash"), symbol: "trash.fill", url: trashURL, hue: 0.0, asset: "TrashIcon"),
    ]
    /// The Trash's desktop icon opens Files at the Trash (FilesExtras.swift).
    static let trashURL = "idesk-trash:"

    @Published var windows: [DeskWindow] = []      // order = stacking order (last = topmost)
    @Published var focusedID: UUID? {
        didSet {
            // Code no app can be found for on the call stack is attributed to the app the user works with.
            if let guest = focused?.guestWindow { GuestRuntime.activateApp(with: guest) }
            // An error report names the app in use (the one most likely to have caused it).
            if let app = focused?.guestApp, focusedID != oldValue { CrashReporter.setGuestName(app.name) }
            if focusedID != oldValue { Self.typingTargetChanged() }
        }
    }

    /// Typing now goes somewhere else: the iPhone's input method starts a new word (see KeyCaptureView).
    static func typingTargetChanged() {
        NotificationCenter.default.post(name: KeyCaptureView.resetNotification, object: nil)
        TextReplacements.typed = ""
    }
    @Published var screenSize: CGSize = CGSize(width: 1280, height: 720) {
        didSet { if screenSize != oldValue { fitWindowsToScreen() } }
    }
    @Published var isExternalConnected = false
    @Published var showLauncher = false {
        didSet {
            if !showLauncher { launcherQuery = "" }
            if showLauncher != oldValue { Self.typingTargetChanged() }
        }
    }
    /// Typed while the app menu is open: filters the apps.
    @Published var launcherQuery = ""
    /// Apps pinned to the taskbar (keys: app bundle id or web address), in order.
    @Published private(set) var pinnedKeys: [String] = UserDefaults.standard.stringArray(forKey: Keys.pinned)
        ?? ["https://www.google.com"] {
        didSet { UserDefaults.standard.set(pinnedKeys, forKey: Keys.pinned) }
    }
    /// The Alt+Tab switcher while it is shown: windows from most to least recent, and the one selected.
    @Published private(set) var switcher: Switcher?
    /// Recent apps (taskbar button or ⌘ + Tab), like the iPhone's app switcher: every window with a picture of it.
    /// Stays open until a window is picked, Esc or a click outside.
    @Published private(set) var recents: Switcher?
    @Published private(set) var thumbnails: [UUID: UIImage] = [:]
    /// Asks the iPhone screen to show one of its sheets (from the desktop's right-click menu).
    @Published var phoneSheet: PhoneSheet?
    @Published var contextMenu: ContextMenu?
    @Published var snapPreview: CGRect?
    /// Spotlight (Spotlight.swift): open, what is typed, the result selected, and the files it searches.
    @Published var showSpotlight = false {
        didSet {
            guard showSpotlight != oldValue else { return }
            spotlightQuery = ""
            spotlightIndex = 0
            spotlightCache = nil
            if showSpotlight { spotlightFiles = Spotlight.indexFiles() }
            Self.typingTargetChanged()
        }
    }
    @Published var spotlightQuery = "" { didSet { spotlightIndex = 0; spotlightCache = nil } }
    @Published var spotlightIndex = 0
    var spotlightFiles: [String] = []
    /// The results for what is typed (the view asks for them many times per frame).
    var spotlightCache: [SpotlightResult]?
    /// The clipboard history panel (Clipboard.swift) and the item selected in it.
    @Published var showClipboard = false { didSet { if showClipboard != oldValue { Self.typingTargetChanged() } } }
    @Published var clipboardIndex = 0
    /// Window layouts: the picker shown while a window is dragged to the top edge, and the zone under the pointer.
    @Published private(set) var showTilePicker = false
    @Published private(set) var tileHover: TileZone?
    /// After a window is put in half or a third of the screen: the windows offered for the rest.
    @Published var fillSuggestion: FillSuggestion?
    @Published private(set) var fillThumbnails: [UUID: UIImage] = [:]
    /// Screenshot of an area (⌘ + Shift + 4): waiting for the area, or being dragged out.
    @Published private(set) var capture: CaptureState?
    /// The last screenshot, shown small in the corner for a moment: a click opens it.
    @Published private(set) var screenshotPreview: ScreenshotPreview?
    private var screenshotPreviewWork: DispatchWorkItem?
    /// Sticky notes on the desktop, and the one being typed in.
    @Published var stickies: [StickyNote] = StickyNote.load() { didSet { StickyNote.save(stickies) } }
    @Published var editingSticky: UUID? { didSet { if editingSticky != oldValue { Self.typingTargetChanged() } } }
    /// Locked (LockScreen.swift): nothing reaches the desktop until Face ID / the passcode on the iPhone.
    @Published var isLocked = false
    /// The screen saver after some minutes without input, and when the last input came.
    @Published var showScreenSaver = false
    var lastInput = Date()
    /// The emoji panel (⌃⌘Space, InputExtras.swift) and the emoji selected in it.
    @Published var showEmoji = false
    @Published var emojiIndex = 0
    /// The Downloads panel (Downloads.swift), opened from its button on the taskbar.
    @Published var showDownloads = false
    /// Task Manager: running windows, memory pressure and close controls.
    @Published var showTaskManager = false
    /// Presentation mode (MediaModes.swift): the window being presented, and the laser pointer on it.
    @Published var presentation: PresentationState?
    @Published var laser: CGPoint?
    /// Hot corners (Settings → Desktop): the pointer in a corner of the screen opens something.
    @Published var hotCorners: Bool = UserDefaults.standard.bool(forKey: Keys.hotCorners) {
        didSet { UserDefaults.standard.set(hotCorners, forKey: Keys.hotCorners) }
    }
    private var hotCornerArmed = true
    private var workspaceWallpapers: [String: Int] = UserDefaults.standard.dictionary(forKey: Keys.workspaceWallpapers) as? [String: Int] ?? [:]
    private let shake = ShakeDetector()
    private var shakeWork: DispatchWorkItem?
    private var hotCornerWork: DispatchWorkItem?
    @Published var selectedIcon: Int?
    @Published var notice: String?                 // error message shown on the iPhone
    @Published private(set) var apps: [GuestApp] = []
    /// Wallpaper: 0…n are the built-in gradients, -1 is the user's photo (`customWallpaper`).
    @Published var wallpaper: Int = UserDefaults.standard.integer(forKey: Keys.wallpaper) {
        didSet {
            UserDefaults.standard.set(wallpaper, forKey: Keys.wallpaper)
            // With workspaces, each one keeps its own wallpaper.
            if workspacesEnabled, workspaceWallpapers[String(workspace)] != wallpaper {
                workspaceWallpapers[String(workspace)] = wallpaper
                UserDefaults.standard.set(workspaceWallpapers, forKey: Keys.workspaceWallpapers)
            }
        }
    }
    @Published private(set) var customWallpaper: UIImage? = UIImage(contentsOfFile: DesktopModel.wallpaperFile.path)
    /// Softens a photo wallpaper (0 = sharp, 20 = heavily blurred). Gradients ignore it.
    /// Lower-resolution frames, lighter shadows and no magnification: useful over AirPlay or a slow Wi-Fi.
    @Published var performanceMode: Bool = UserDefaults.standard.bool(forKey: Keys.performanceMode) {
        didSet { UserDefaults.standard.set(performanceMode, forKey: Keys.performanceMode) }
    }
    @Published var wallpaperBlur: Double = DockSettings.clamp(
        UserDefaults.standard.object(forKey: Keys.wallpaperBlur) as? Double ?? 0, to: 0...20) {
        didSet { UserDefaults.standard.set(wallpaperBlur, forKey: Keys.wallpaperBlur) }
    }
    /// External display brightness (0.2…1). Apps cannot change its backlight, so it is dimmed with an overlay.
    @Published var externalBrightness: Double = UserDefaults.standard.object(forKey: Keys.brightness) as? Double ?? 1 {
        didSet { UserDefaults.standard.set(externalBrightness, forKey: Keys.brightness) }
    }
    /// How many windows can be open at once (0: no limit). Every app runs inside iDesk's own process, so each
    /// open one makes everything a little slower.
    /// -1: automatic (as many as memory allows), 0: no limit, otherwise that many.
    @Published var maxWindows: Int = UserDefaults.standard.object(forKey: Keys.maxWindows) as? Int ?? -1 {
        didSet { UserDefaults.standard.set(maxWindows, forKey: Keys.maxWindows) }
    }
    /// The dock slides away and comes back when the pointer touches the bottom edge of the screen.
    @Published var autoHideTaskbar: Bool = UserDefaults.standard.bool(forKey: Keys.autoHideTaskbar) {
        didSet { UserDefaults.standard.set(autoHideTaskbar, forKey: Keys.autoHideTaskbar); updateHover(cursor.position) }
    }
    /// Floating dock appearance (APLite). All of these are live: changing one redraws the desktop.
    @Published var dockScale: Double = DockSettings.clamp(DockSettings.double(DockSettings.scaleKey, default: DockSettings.defaultScale), to: DockSettings.scaleRange) {
        didSet { UserDefaults.standard.set(dockScale, forKey: DockSettings.scaleKey) }
    }
    @Published var dockIconScale: Double = DockSettings.clamp(DockSettings.double(DockSettings.iconScaleKey, default: DockSettings.defaultIconScale), to: DockSettings.iconScaleRange) {
        didSet { UserDefaults.standard.set(dockIconScale, forKey: DockSettings.iconScaleKey) }
    }
    @Published var dockSpacing: Double = DockSettings.clamp(DockSettings.double(DockSettings.spacingKey, default: DockSettings.defaultSpacing), to: DockSettings.spacingRange) {
        didSet { UserDefaults.standard.set(dockSpacing, forKey: DockSettings.spacingKey) }
    }
    @Published var dockOpacity: Double = DockSettings.clamp(DockSettings.double(DockSettings.opacityKey, default: DockSettings.defaultOpacity), to: DockSettings.opacityRange) {
        didSet { UserDefaults.standard.set(dockOpacity, forKey: DockSettings.opacityKey) }
    }
    @Published var dockMagnification: Bool = UserDefaults.standard.object(forKey: DockSettings.magnificationKey) as? Bool ?? DockSettings.defaultMagnification {
        didSet { UserDefaults.standard.set(dockMagnification, forKey: DockSettings.magnificationKey) }
    }
    @Published var dockAppearance: Int = UserDefaults.standard.object(forKey: DockSettings.appearanceKey) as? Int ?? DockSettings.defaultAppearance.rawValue {
        didSet { UserDefaults.standard.set(dockAppearance, forKey: DockSettings.appearanceKey) }
    }
    @Published private(set) var taskbarRevealed = false
    /// A picture of the window under the pointer on the taskbar.
    @Published private(set) var taskPreview: TaskPreview?
    private var taskPreviewWork: DispatchWorkItem?
    /// A short-lived visual of a window flying back to its dock icon while it closes.
    @Published private(set) var closingWindow: ClosingWindow?
    private var closingWork: DispatchWorkItem?
    /// Quick panel (click the clock): quick toggles, brightness, notifications.
    @Published var showQuickPanel = false {
        didSet { if showQuickPanel { showLauncher = false; contextMenu = nil; banner = nil } }
    }
    @Published private(set) var notifications: [DeskNotification] = []
    /// The newest notification, shown for a few seconds at the top right.
    @Published private(set) var banner: DeskNotification?
    private var bannerWork: DispatchWorkItem?
    @Published var doNotDisturb: Bool = UserDefaults.standard.bool(forKey: Keys.doNotDisturb) {
        didSet { UserDefaults.standard.set(doNotDisturb, forKey: Keys.doNotDisturb) }
    }
    /// Clock and calendar widgets on the desktop, behind the windows.
    /// Desktop icon size: 0 small, 1 medium (default), 2 large; for a 4K screen or a TV across the room.
    @Published var iconSize: Int = UserDefaults.standard.object(forKey: Keys.iconSize) as? Int ?? 1 {
        didSet { UserDefaults.standard.set(iconSize, forKey: Keys.iconSize) }
    }
    static func iconScale(_ size: Int) -> CGFloat {
        guard UserDefaults.standard.object(forKey: Keys.iconSize) != nil else { return 1 }
        return [0.8, 1, 1.3][min(max(size, 0), 2)]
    }

    @Published var showWidgets: Bool = UserDefaults.standard.object(forKey: Keys.showWidgets) as? Bool ?? true {
        didSet { UserDefaults.standard.set(showWidgets, forKey: Keys.showWidgets) }
    }
    /// The keyboard shortcuts panel (⌘ + /).
    @Published var showShortcuts = false
    /// iOS apps whose windows were open when iDesk last closed open again (Settings → Windows), unless iDesk quit
    /// unexpectedly last time: one of them may be why, and opening it again would repeat it.
    @Published var reopenApps: Bool = UserDefaults.standard.object(forKey: Keys.reopenApps) as? Bool ?? true {
        didSet { UserDefaults.standard.set(reopenApps, forKey: Keys.reopenApps) }
    }
    /// The last run ended with a crash or with iOS closing iDesk (see init).
    private var lastRunFailed = false
    /// The iOS app in use when iDesk quit unexpectedly last time.
    private(set) var problemApp: String?
    /// The last run's crash report (shown as a short notice; sent with "Send report" or copied).
    var crashReport: String?

    /// A GitHub issue filled in with the crash report, the iPhone and the versions; the user only presses Submit.
    /// (iDesk can't file it by itself: that would need a GitHub token inside the app, which anyone could take.)
    var crashReportURL: URL? {
        guard let report = crashReport else { return nil }
        var model = utsname(); uname(&model)
        let machine = withUnsafeBytes(of: &model.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let short = report.count > 3000 ? String(report.prefix(3000)) + "\n…" : report
        let body = """
        **APLite:** \(UpdateChecker.current)
        **iPhone / iPad:** \(machine), iOS \(UIDevice.current.systemVersion)
        **App đang mở / App in use:** \(problemApp ?? "-")
        **Lúc đó đang làm gì? / What were you doing?**


        ```
        \(short)
        ```
        """
        var c = URLComponents(string: "https://github.com/\(APLite.repository)/issues/new")!
        c.queryItems = [URLQueryItem(name: "title", value: "[Crash] APLite \(UpdateChecker.current)" + (problemApp.map { " · \($0)" } ?? "")),
                        URLQueryItem(name: "labels", value: "crash"),
                        URLQueryItem(name: "body", value: body)]
        return c.url
    }
    /// The workspace (virtual desktop) shown, 0…workspaceCount-1: four of them.
    @Published private(set) var workspace = 0
    /// Workspaces are off unless turned on in Settings → Desktop: then the taskbar shows 1 2 3 4, and the keys and
    /// the four-finger swipe switch between them. Turning them off brings every window back to the one desktop.
    @Published var workspacesEnabled: Bool = UserDefaults.standard.bool(forKey: Keys.workspaces) {
        didSet {
            UserDefaults.standard.set(workspacesEnabled, forKey: Keys.workspaces)
            if !workspacesEnabled {
                setWorkspace(0)
                for w in windows { w.workspace = 0; w.isOffDesk = false }
                scheduleSave()
            }
            updateHover(cursor.position)
        }
    }
    static let workspaceCount = 4
    /// A short message on the desktop; goes away by itself.
    @Published private(set) var toast: String?
    private var toastWork: DispatchWorkItem?
    let cursor = CursorModel()

    /// Where the settings are kept (UserDefaults).
    enum Keys {
        static let wallpaper = "iDesk.wallpaper"
        static let wallpaperBlur = "APLite.wallpaperBlur"
        static let performanceMode = "APLite.performanceMode"
        static let brightness = "iDesk.externalBrightness"
        static let session = "iDesk.session.v1"
        static let pinned = "iDesk.pinned"
        static let recentItems = "iDesk.recentItems"
        static let desktopHiddenApps = "iDesk.desktopHiddenApps"
        static let desktopFiles = "iDesk.desktopFiles"
        static let iconSlots = "iDesk.iconCells"
        static let maxWindows = "iDesk.maxWindows"
        static let autoHideTaskbar = "iDesk.autoHideTaskbar"
        static let appFrames = "iDesk.appFrames"
        static let doNotDisturb = "iDesk.doNotDisturb"
        static let showWidgets = "iDesk.showWidgets"
        static let iconSize = "iDesk.iconSize"
        static let workspaces = "iDesk.workspaces"
        static let openApps = "iDesk.session.apps.v1"
        static let workedApps = "iDesk.appsThatWorked"
        static let reopenApps = "iDesk.reopenApps"
        static let hotCorners = "iDesk.hotCorners"
        static let workspaceWallpapers = "iDesk.workspaceWallpapers"
    }

    private enum Drag {
        case none
        case move(UUID, offset: CGPoint)
        case resize(UUID, edges: ResizeEdges, start: CGPoint, startFrame: CGRect)
        case guest(UUID)            // holding a "finger" down in a guest app
        case icon(Shortcut, from: CGPoint)   // pressed on an icon (desktop, app menu, a file in Files): moving drags it
        case filePending(from: CGPoint)      // pressed in Files: waiting for the page to say which file is there
        case sticky(UUID, offset: CGPoint)   // moving a sticky note by its top strip
        case widget(WidgetKind, offset: CGPoint)   // moving a desktop widget
    }
    enum Snap {
        case left, right, maximize, topLeft, topRight, bottomLeft, bottomRight
        case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    }
    enum PhoneSheet { case apps, settings, welcome }

    struct TaskPreview {
        let id: UUID
        let title: String
        let image: UIImage?
        let anchor: CGRect
    }

    struct ClosingWindow: Identifiable {
        let id = UUID()
        let title: String
        let icon: UIImage?
        let symbol: String
        let from: CGRect
        let to: CGRect
    }
    enum NavButton: CaseIterable { case search, recents, home, back }

    struct Switcher {
        var ids: [UUID]
        var index: Int
    }

    /// A taskbar entry: a pinned app (with its window when it is open) or another open window.
    enum TaskEntry {
        case pinned(Shortcut, DeskWindow?)
        case window(DeskWindow)

        var window: DeskWindow? {
            switch self {
            case let .pinned(_, w): return w
            case let .window(w): return w
            }
        }
    }

    private var drag: Drag = .none
    private var snapTarget: Snap?
    private var pressPoint: CGPoint?
    private var lastClickTime: CFTimeInterval = 0
    private var lastClickPoint: CGPoint = .zero
    private var hiddenByShowDesktop: [UUID] = []
    private var hoverInFlight = false
    private var hoverStarted: CFTimeInterval = 0
    private var hoverAgain = false
    private var saveWork: DispatchWorkItem?
    private var switcherCommit: DispatchWorkItem?
    private var appsSubscription: AnyCancellable?
    private var pagesSubscription: AnyCancellable?
    private var browsingSubscription: AnyCancellable?
    private var webAppsSubscription: AnyCancellable?
    private var updatesSubscription: AnyCancellable?
    /// `items` walks guest apps, bookmarks, web apps and built-ins; the dock and the launcher ask for it
    /// on every pointer move and every redraw. Cache it and invalidate only when a source changes.
    private var itemsRevision = 0
    private var cachedItems: [Shortcut]?
    private var cachedItemsRevision = -1
    private var isDragging: Bool { if case .none = drag { return false } else { return true } }
    private var isGuestDrag: Bool { if case .guest = drag { return true } else { return false } }

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.memoryIsLow() }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.saveNow()
            self?.pausedAt = Date()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.resumed()
            self?.lockDesktop()          // back after the iPhone was locked or another app was used
        }
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.checkIdle() }
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.thermalChanged() }
        NotificationCenter.default.addObserver(forName: UIDevice.batteryLevelDidChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.batteryChanged() }
        ContentBlocker.prepare()
        appsSubscription = GuestStore.shared.$apps.sink { [weak self] in
            self?.apps = $0
            self?.invalidateItems()
        }
        browsingSubscription = Browsing.shared.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
            self?.invalidateItems()
        }
        webAppsSubscription = WebApps.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.invalidateItems() }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.invalidateItems() }
        updatesSubscription = UpdateChecker.shared.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
        // Settings and Apps pages follow changes made anywhere (keys, quick panel, the iPhone, installs).
        pagesSubscription = objectWillChange.merge(with: GuestStore.shared.objectWillChange, SigningStore.shared.objectWillChange,
                                                   NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in })
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { DesktopPages.refresh() }
        // A guest app opened an in-app browser (GuestRuntimeOpenURLNotification): a web window on the desktop.
        NotificationCenter.default.addObserver(forName: Notification.Name("iDeskGuestOpenURL"),
                                               object: nil, queue: .main) { [weak self] note in
            if let url = note.object as? URL { self?.openWindow(url.absoluteString) }
        }
        // A guest app's notification is due (GuestRuntimeNotificationNotification).
        NotificationCenter.default.addObserver(forName: Notification.Name("iDeskGuestNotification"),
                                               object: nil, queue: .main) { [weak self] note in
            self?.receiveGuestNotification(note.userInfo as? [String: String] ?? [:])
        }
        // iDesk quit last time (usually because of a guest app): show the report so the user can send it.
        let report = CrashReporter.takeLastReport()
        // The app named in the report (the one in use) is marked on the Apps page until the next clean run.
        problemApp = report.flatMap { text in
            text.range(of: #"[Gg]uest app: ([^\n]+)"#, options: .regularExpression).map {
                String(text[$0].dropFirst("guest app: ".count)).trimmingCharacters(in: .whitespaces)
            }
        }.flatMap { $0 == "(none)" ? nil : $0 }
        if let report {
            lastRunFailed = true
            // The apps open then are not reopened later either (the one at fault would take iDesk down again).
            UserDefaults.standard.removeObject(forKey: Keys.openApps)
            if let name = problemApp {
                let bad = GuestStore.shared.apps.filter { $0.name == name }.map(\.id)
                UserDefaults.standard.set(workedApps.filter { !bad.contains($0) }, forKey: Keys.workedApps)
            }
            crashReport = report.count > 6000 ? String(report.prefix(6000)) + "\n…" : report
            notice = problemApp.map { String(localized: "APLite closed unexpectedly last time, while \($0) was open.") }
                ?? String(localized: "APLite closed unexpectedly last time.")
        }
    }

    /// Everything that can be opened from the desktop / app menu: web shortcuts + installed apps.
    /// Everything on the desktop and in the app menu: built-in shortcuts (minus those the user removed), pages the
    /// user added, iDesk's own pages, then installed apps.
    var items: [Shortcut] {
        if let cachedItems, cachedItemsRevision == itemsRevision { return cachedItems }
        let browsing = Browsing.shared
        // A web shortcut named like an installed app ("YouTube" and the YouTube app) says it is the website.
        let appNames = Set(apps.map { $0.name.lowercased() })
        let builtIn = Self.shortcuts.filter { !browsing.hiddenShortcuts.contains($0.url) }.map { s -> Shortcut in
            guard appNames.contains(s.name.lowercased()) else { return s }
            return Shortcut(name: String(localized: "\(s.name) (web)"), symbol: s.symbol, url: s.url, hue: s.hue)
        }
        let links = browsing.desktopLinks.map { Shortcut(name: $0.title, symbol: "globe", url: $0.url, hue: Self.hue(for: $0.url)) }
        func isOwn(_ s: Shortcut) -> Bool { DesktopPage(URL(string: s.url)) != nil || s.url == Self.trashURL }
        let own = builtIn.filter(isOwn), web = builtIn.filter { !isOwn($0) }
        let webApps = WebApps.shared.all.map { Shortcut(name: $0.title, symbol: "app.badge", url: $0.url, hue: Self.hue(for: $0.url), webApp: true) }
        let result = web + links + webApps + own + apps.map { Shortcut(name: $0.name, symbol: "app.fill", url: "", hue: 0.5, app: $0) }
        cachedItems = result
        cachedItemsRevision = itemsRevision
        return result
    }

    private func invalidateItems() { itemsRevision &+= 1; cachedItems = nil }

    /// A stable colour per site for the icon of a page added to the desktop.
    private static func hue(for url: String) -> Double {
        let host = URL(string: url)?.host ?? url
        return Double(host.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % 100) / 100
    }

    func open(_ item: Shortcut) {
        noteRecent(item)
        if let app = item.app { openApp(app) }
        else if let file = item.file { openFile(file) }
        else if item.url == Self.trashURL { openFile(Trash.folder) }
        else if item.webApp { openWebApp(item.url) }
        else { openWindow(item.url) }
    }

    /// A file from Files (a path inside it): text files in the editor, others in a browser window; a folder in a
    /// Files window.
    func openFile(_ path: String) {
        guard let url = FileStore.resolve(path), FileManager.default.fileExists(atPath: url.path) else {
            showToast(String(localized: "“\((path as NSString).lastPathComponent)” is no longer in Files.")); return
        }
        if FileStore.isFolder(url) {
            openPage(.files)
            if let w = windows.last(where: { $0.systemPage == .files }) { w.showFolder(path) }
            return
        }
        if TextEditor.canEdit(url) { openWindow(TextEditor.url(for: path)); return }
        openWindow(url)
    }

    /// A file or folder of Files was renamed or moved: its desktop shortcut (and those inside a moved folder)
    /// follow it.
    func fileMoved(from old: String, to new: String) {
        func moved(_ path: String) -> String? {
            if path == old { return new }
            if path.hasPrefix(old + "/") { return new + path.dropFirst(old.count) }
            return nil
        }
        if desktopFiles.contains(where: { moved($0) != nil }) {
            var slots = iconSlots
            for path in desktopFiles { if let n = moved(path), let slot = slots.removeValue(forKey: "file:" + path) { slots["file:" + n] = slot } }
            iconSlots = slots
            desktopFiles = desktopFiles.map { moved($0) ?? $0 }
        }
        for w in windows { if let s = w.selectedFile, let n = moved(s) { w.selectedFile = n } }
    }

    // MARK: Desktop icons

    /// Apps taken off the desktop (they stay in the app menu; dragging one back puts it on the desktop again).
    @Published private(set) var desktopHiddenApps: [String] = UserDefaults.standard.stringArray(forKey: Keys.desktopHiddenApps) ?? [] {
        didSet { UserDefaults.standard.set(desktopHiddenApps, forKey: Keys.desktopHiddenApps) }
    }
    /// Files dragged from Files onto the desktop (names in Downloads).
    @Published private(set) var desktopFiles: [String] = UserDefaults.standard.stringArray(forKey: Keys.desktopFiles) ?? [] {
        didSet { UserDefaults.standard.set(desktopFiles, forKey: Keys.desktopFiles) }
    }
    /// Where each icon was put: a cell of the desktop grid, column × 1000 + row, so icons keep their column and row
    /// when the icon size or the display changes. Icons not placed by the user fill the first free cells, in order.
    @Published private(set) var iconSlots: [String: Int] = (UserDefaults.standard.dictionary(forKey: Keys.iconSlots) as? [String: Int]) ?? [:] {
        didSet { UserDefaults.standard.set(iconSlots, forKey: Keys.iconSlots) }
    }
    /// The icon being dragged (drawn under the pointer) and the desktop cell it would land in.
    @Published private(set) var iconDrag: Shortcut?
    @Published private(set) var iconDropSlot: Int?

    /// What is on the desktop: the app menu's items minus the apps taken off it, plus the files put on it.
    var desktopItems: [Shortcut] {
        let hidden = Set(desktopHiddenApps)
        let files = desktopFiles.compactMap { name -> Shortcut? in
            guard let url = FileStore.resolve(name), FileManager.default.fileExists(atPath: url.path) else { return nil }
            let symbol = FileStore.isFolder(url) ? "folder.fill" : FileStore.iconSymbol(for: url.pathExtension)
            return Shortcut(name: url.lastPathComponent, symbol: symbol, url: url.absoluteString, hue: 0.6, file: name)
        }
        return items.filter { $0.app.map { !hidden.contains($0.id) } ?? true } + files
    }

    /// Each desktop icon with its cell.
    var desktopLayout: [(item: Shortcut, slot: Int)] {
        var used = Set<Int>(), placed: [(item: Shortcut, slot: Int)] = [], rest: [Shortcut] = []
        let rows = iconsPerColumn, cols = iconColumns
        for item in desktopItems {
            if let slot = iconSlots[Self.key(of: item)], slot / 1000 < cols, slot % 1000 < rows, !used.contains(slot) {
                used.insert(slot)
                placed.append((item, slot))
            } else {
                rest.append(item)
            }
        }
        let free = freeCells(excluding: used).makeIterator()
        for item in rest { if let cell = free.next() { placed.append((item, cell)) } }
        return placed
    }

    /// Free cells down each column, left to right (past the last column if the desktop is full).
    private func freeCells(excluding used: Set<Int>) -> AnySequence<Int> {
        let rows = iconsPerColumn
        return AnySequence((0..<200).lazy.flatMap { col in (0..<rows).lazy.map { col * 1000 + $0 } }.filter { !used.contains($0) })
    }

    private var iconsPerColumn: Int {
        max(1, Int((taskbarTop - Layout.iconOrigin.y) / (Layout.iconCell.height + Layout.iconGap)))
    }
    private var iconColumns: Int {
        max(1, Int((screenSize.width - Layout.iconOrigin.x) / (Layout.iconCell.width + Layout.iconGap)))
    }

    /// The desktop cell under a point, if the point is on the desktop itself (not over a window or the taskbar).
    private func dropSlot(at p: CGPoint) -> Int? {
        guard p.y < taskbarHitTop, topWindow(at: p) == nil else { return nil }
        let c = Layout.iconCell, g = Layout.iconGap, o = Layout.iconOrigin
        let col = Int(floor((p.x - o.x + g / 2) / (c.width + g))), row = Int(floor((p.y - o.y + g / 2) / (c.height + g)))
        guard col >= 0, row >= 0, col < iconColumns, row < iconsPerColumn else { return nil }
        return col * 1000 + row
    }

    private func desktopIcon(at p: CGPoint) -> (item: Shortcut, slot: Int)? {
        desktopLayout.first { iconRect($0.slot).contains(p) }
    }

    /// Puts an icon on the desktop (an app back from the app menu, a file from Files) or moves it, into a cell.
    /// Whatever is in that cell takes the dragged icon's old place. Every icon keeps its place from then on.
    private func dropOnDesktop(_ item: Shortcut, slot: Int) {
        if let app = item.app { desktopHiddenApps.removeAll { $0 == app.id } }
        else if let file = item.file { if !desktopFiles.contains(file) { desktopFiles.append(file) } }
        else if !Browsing.shared.isOnDesktop(item.url), let url = URL(string: item.url) {
            Browsing.shared.addToDesktop(url, title: item.name)
        }
        let key = Self.key(of: item)
        var slots = desktopLayout.reduce(into: [String: Int]()) { $0[Self.key(of: $1.item)] = $1.slot }
        if let other = slots.first(where: { $0.value == slot && $0.key != key })?.key {
            if let from = slots[key] { slots[other] = from }
            else {
                slots[other] = freeCells(excluding: Set(slots.values)).makeIterator().next()
            }
        }
        slots[key] = slot
        iconSlots = slots
        selectedIcon = slot
    }

    func removeFromDesktop(_ item: Shortcut) {
        if let app = item.app { if !desktopHiddenApps.contains(app.id) { desktopHiddenApps.append(app.id) } }
        else if let file = item.file { desktopFiles.removeAll { $0 == file } }
        else { Browsing.shared.removeFromDesktop(item.url) }
        selectedIcon = nil
    }

    private func isOnDesktop(_ item: Shortcut) -> Bool {
        let key = Self.key(of: item)
        return desktopItems.contains { Self.key(of: $0) == key }
    }

    // MARK: Quick Look

    /// The file previewed over the desktop (Space in Files), if any.
    @Published var quickLook: URL? {
        didSet { if oldValue != quickLook { QuickLook.stop() } }
    }
    private var quickLookWindow: UUID?

    var quickLookRect: CGRect {
        let w = min(1100, screenSize.width * 0.72), h = min(820, taskbarTop * 0.84)
        return CGRect(x: (screenSize.width - w) / 2, y: (taskbarTop - h) / 2, width: w, height: h).integral
    }

    /// Space in Files: previews the selected file (a folder opens); Space again closes it.
    func toggleQuickLook() {
        if quickLook != nil { quickLook = nil; return }
        guard let w = focused, w.systemPage == .files else { return }
        guard let path = w.selectedFile, let url = FileStore.resolve(path), FileManager.default.fileExists(atPath: url.path) else {
            showToast(String(localized: "Click a file, then press Space to preview it."))
            return
        }
        if FileStore.isFolder(url) { w.showFolder(path); return }
        quickLookWindow = w.id
        quickLook = url
    }

    /// ← → ↑ ↓ while previewing: the previous / next file, in the order the Files window shows them.
    private func stepQuickLook(_ delta: Int) {
        guard quickLook != nil, let id = quickLookWindow, let w = window(id) else { return }
        w.webView?.evaluateJavaScript("window.ideskStep && ideskStep(\(delta))")
    }

    /// The Files page selected another file while Quick Look shows one from it: show that one.
    func quickLookFollowSelection(in w: DeskWindow) {
        guard quickLook != nil, quickLookWindow == w.id, let path = w.selectedFile,
              let url = FileStore.resolve(path), !FileStore.isFolder(url) else { return }
        quickLook = url
    }

    // MARK: Pinned apps (taskbar)

    static func key(of item: Shortcut) -> String {
        item.app?.id ?? item.file.map { "file:" + $0 } ?? (item.webApp ? "webapp:" + item.url : item.url)
    }

    var pinnedItems: [Shortcut] {
        let all = items
        return pinnedKeys.compactMap { key in all.first { Self.key(of: $0) == key } }
    }

    func isPinned(_ item: Shortcut) -> Bool { pinnedKeys.contains(Self.key(of: item)) }

    func togglePin(_ item: Shortcut) {
        let key = Self.key(of: item)
        if let i = pinnedKeys.firstIndex(of: key) { pinnedKeys.remove(at: i) } else { pinnedKeys.append(key) }
    }

    /// Pinned apps first (an open app shows its window there, as in a dock), then the other windows.
    var taskEntries: [TaskEntry] {
        var shown = Set<UUID>()
        var entries: [TaskEntry] = pinnedItems.map { item in
            let w = item.app.flatMap { app in windows.first { $0.guestApp == app } }
            if let w { shown.insert(w.id) }
            return .pinned(item, w)
        }
        entries += deskWindows.filter { !shown.contains($0.id) }.map { .window($0) }
        return entries
    }

    /// Nothing in the app menu matches what was typed: search the web for it in a new window.
    func searchWebFromLauncher() {
        let q = launcherQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        showLauncher = false
        openWindow(q)
    }

    /// The "Search the web" row shown in the app menu when no app matches.
    /// The app menu ends with how to add iOS apps while there are none (and nothing is typed).
    var launcherShowsAppsHint: Bool { apps.isEmpty && launcherQuery.isEmpty }

    var launcherAppsHintRect: CGRect {
        let r = launcherRect
        return CGRect(x: r.minX + Layout.launcherPadding, y: r.maxY - Layout.launcherPadding - Layout.launcherFooter + 6,
                      width: r.width - Layout.launcherPadding * 2, height: Layout.launcherFooter - 6)
    }

    var launcherSearchRect: CGRect {
        let r = launcherRect
        return CGRect(x: r.minX + Layout.launcherPadding, y: r.minY + Layout.launcherPadding + Layout.launcherHeader + 22,
                      width: r.width - Layout.launcherPadding * 2, height: 32)
    }

    /// The app menu: the recently opened row (when nothing is typed), then the apps, filtered by what was typed.
    var launcherItems: [Shortcut] {
        let q = launcherQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return launcherRecents + items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    /// Apps and pages opened last (one row of the app menu), most recent first.
    @Published private(set) var recentKeys: [String] = UserDefaults.standard.stringArray(forKey: Keys.recentItems) ?? [] {
        didSet { UserDefaults.standard.set(recentKeys, forKey: Keys.recentItems) }
    }

    var launcherRecents: [Shortcut] {
        guard launcherQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let all = items
        return Array(recentKeys.compactMap { key in all.first { Self.key(of: $0) == key } }.prefix(Layout.launcherColumns))
    }

    private func noteRecent(_ item: Shortcut) {
        guard item.file == nil else { return }
        let key = Self.key(of: item)
        var keys = recentKeys.filter { $0 != key }
        keys.insert(key, at: 0)
        recentKeys = Array(keys.prefix(8))
    }

    private func itemMenu(_ item: Shortcut) -> [MenuItem] {
        var menu = [
            MenuItem("Open", "arrow.up.forward.app") { [weak self] in self?.showLauncher = false; self?.open(item) },
        ]
        if item.file == nil {
            menu.append(MenuItem(isPinned(item) ? "Unpin from taskbar" : "Pin to taskbar",
                                 isPinned(item) ? "pin.slash" : "pin") { [weak self] in self?.togglePin(item) })
        }
        if item.app != nil {
            // An app stays in the app menu; only its desktop icon goes (dragging it back from the menu returns it).
            menu += isOnDesktop(item)
                ? [.separator, MenuItem("Remove from desktop", "minus.circle") { [weak self] in self?.removeFromDesktop(item) }]
                : [.separator, MenuItem("Add to desktop", "plus.circle") { [weak self] in
                    if let id = item.app?.id { self?.desktopHiddenApps.removeAll { $0 == id } }
                }]
        } else if item.file != nil {
            menu += [.separator, MenuItem("Remove from desktop", "minus.circle") { [weak self] in self?.removeFromDesktop(item) }]
        } else if item.webApp {
            menu += [.separator, MenuItem("Remove app", "trash") { [weak self] in
                WebApps.shared.remove(item.url)
                self?.pinnedKeys.removeAll { $0 == Self.key(of: item) }
                self?.objectWillChange.send()
            }]
        } else if DesktopPage(URL(string: item.url)) == nil {
            // A web page (built-in or added by the user) is taken off the desktop and the app menu.
            menu += [.separator, MenuItem("Remove from desktop", "minus.circle") { [weak self] in self?.removeFromDesktop(item) }]
        }
        return menu
    }

    var focused: DeskWindow? { windows.first { $0.id == focusedID } }
    var taskbarTop: CGFloat { screenSize.height - Layout.taskbar }
    /// Where windows go: above the taskbar, or the whole screen when the taskbar hides itself.
    var desktopArea: CGRect {
        CGRect(x: 0, y: 0, width: screenSize.width, height: max(0, autoHideTaskbar ? screenSize.height : taskbarTop))
    }
    private var maximizedFrame: CGRect { desktopArea.insetBy(dx: 4, dy: 4) }

    private func window(_ id: UUID) -> DeskWindow? { windows.first { $0.id == id } }

    // MARK: The iPhone: paused, hot, low battery

    /// When iDesk went to the background (the iPhone locked, or another app opened on it): nothing runs then, and
    /// the display shows the iPhone's own screen.
    private var pausedAt: Date?
    private var lastHeatWarning: ProcessInfo.ThermalState = .nominal
    private var lastBatteryWarning = 100

    private func resumed() {
        defer { pausedAt = nil }
        guard isExternalConnected, let pausedAt, Date().timeIntervalSince(pausedAt) > 3 else { return }
        showToast(String(localized: "APLite was paused while the iPhone was locked or showing another app. Keep APLite open on the iPhone while you work."))
    }

    private func thermalChanged() {
        let state = ProcessInfo.processInfo.thermalState
        defer { lastHeatWarning = state }
        guard isExternalConnected, state.rawValue > lastHeatWarning.rawValue else { return }
        switch state {
        case .serious:
            showToast(String(localized: "The iPhone is getting hot. Close windows you don't need, take it out of its case or lower the display resolution."))
        case .critical:
            showToast(String(localized: "The iPhone is very hot and will slow down. Close some windows and let it cool."))
        default: break
        }
    }

    private func batteryChanged() {
        let device = UIDevice.current
        guard device.batteryLevel >= 0 else { return }
        let percent = Int((device.batteryLevel * 100).rounded())
        if device.batteryState == .charging || device.batteryState == .full { lastBatteryWarning = 100; return }
        guard isExternalConnected, let mark = [10, 20].first(where: { percent <= $0 && $0 < lastBatteryWarning }) else { return }
        lastBatteryWarning = mark
        showToast(String(localized: "Battery \(percent)%. Use a USB-C hub with a power port to charge the iPhone while you work."))
    }

    // MARK: Display connection

    /// iOS is running out of memory: give back what can come back by itself, before iOS closes iDesk with every
    /// app in it. Web caches go, and the tabs nobody is looking at are emptied (they load again when selected).
    func memoryIsLow() {
        URLCache.shared.removeAllCachedResponses()
        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeMemoryCache], modifiedSince: .distantPast) {}
        let n = windows.reduce(0) { $0 + $1.discardBackgroundTabs() }
        if n > 0 { showToast(String(localized: "Memory is low: \(n) tabs you weren't using were set aside. They reload when you open them.")) }
    }

    func externalConnected() {
        isExternalConnected = true
        UIApplication.shared.isIdleTimerDisabled = true
        cursor.position = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
        if windows.isEmpty {
            if !restoreSession() { openWindow("https://www.google.com") }
            reopenSavedApps()
        }
    }

    /// Opens the iOS apps of the last session one after the other (each takes a moment to start).
    /// Apps that have run in a window for a while without iDesk quitting: only these reopen by themselves.
    private var workedApps: [String] { UserDefaults.standard.stringArray(forKey: Keys.workedApps) ?? [] }

    private func reopenSavedApps() {
        let ids = UserDefaults.standard.stringArray(forKey: Keys.openApps) ?? []
        guard reopenApps, !lastRunFailed, !ids.isEmpty else { return }
        let worked = Set(workedApps)
        let apps = ids.compactMap { id in GuestStore.shared.apps.first {
            $0.id == id && worked.contains(id) && !$0.pendingRemoval && GuestStore.shared.opensRightAway($0)
        } }
        for (i, app) in apps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 + 1.5 * Double(i)) { [weak self] in
                guard let self, isExternalConnected else { return }
                openApp(app)
            }
        }
    }

    func externalDisconnected() {
        saveNow()
        isExternalConnected = false
        UIApplication.shared.isIdleTimerDisabled = false
        drag = .none
        contextMenu = nil
        snapPreview = nil
    }

    // MARK: Windows

    func openWindow(_ string: String) { openWindow(Self.url(from: string)) }

    func openWindow(_ url: URL, webApp: Bool = false) {
        // No external display means no desktop to put the window on: do not open it invisibly.
        guard isExternalConnected else { return }
        let page = DesktopPage(url)
        // iDesk's own pages (Files, Settings, Apps): one window each, brought to the front if already open;
        // they are light, so the window limit does not apply to them.
        // (The editor: one window per file.)
        if let page, let w = windows.first(where: { w in w.tab(showing: page) != nil && (page != .editor || w.tabs.contains { $0.url == url }) }),
           let i = page == .editor ? w.tabs.firstIndex(where: { $0.url == url }) : w.tab(showing: page) {
            w.selectTab(i)
            focus(w)
            return
        }
        guard page != nil || canOpenAnother() else { return }
        let area = desktopArea
        let size = page.map { CGSize(width: min($0.windowSize.width, area.width - 16), height: min($0.windowSize.height, area.height - 16)) }
            ?? CGSize(width: min(1100, area.width * 0.72), height: min(760, area.height * 0.8))
        let step = CGFloat(windows.count % 8) * 32
        let origin = CGPoint(x: max(0, (area.width - size.width) / 2 - 96 + step),
                             y: max(0, (area.height - size.height) / 2 - 48 + step))
        let w = DeskWindow(url: url, frame: CGRect(origin: origin, size: size))
        w.isWebApp = webApp
        add(w)
        focusedID = w.id
        scheduleSave()
    }

    /// The display changed size (another resolution, another display): maximized and snapped windows take their
    /// place on the new screen; the others stay where they were but are brought back on screen and made to fit.
    private func fitWindowsToScreen() {
        let area = desktopArea
        guard area.width > 100, area.height > 100 else { return }
        for w in windows {
            if w.isFullscreen { w.frame = CGRect(origin: .zero, size: screenSize); continue }
            if w.isMaximized { w.frame = maximizedFrame; continue }
            if w.isSnapped, let s = w.snap { w.frame = snapRect(s); continue }
            var f = w.frame
            f.size.width = min(f.width, area.width)
            f.size.height = min(f.height, area.height)
            f.origin.x = min(max(area.minX, f.minX), area.maxX - f.width)
            f.origin.y = min(max(area.minY, f.minY), area.maxY - f.height)
            if f != w.frame { w.frame = f }
        }
        stickies = stickies.map { n in
            var n = n
            n.x = min(max(0, n.x), Double(screenSize.width) - 60)
            n.y = min(max(0, n.y), Double(taskbarTop) - Double(StickyNote.header))
            return n
        }
    }

    /// A file from Files dropped on a web page: put in the file field under it, or dropped on the page the way a
    /// computer drops a file (Gmail, Drive, WhatsApp Web… take it as an upload).
    private func uploadFile(_ path: String, to w: DeskWindow, at point: CGPoint) {
        guard let url = FileStore.resolve(path), !FileStore.isFolder(url), let web = w.webView else {
            showToast(String(localized: "Drop a file, not a folder, on the page.")); return
        }
        guard let data = try? Data(contentsOf: url), data.count <= 40_000_000 else {
            showToast(String(localized: "This file is too big to drop on a page (40 MB at most).")); return
        }
        focus(w)
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        WebInput.dropFile(web, at: point, name: url.lastPathComponent, type: type, data: data) { [weak self] ok in
            if !ok { self?.showToast(String(localized: "The page did not take the file.")) }
        }
    }

    #if DEBUG
    /// Test helper: a file of Files dropped at a point, as if dragged there.
    func debugDropFile(_ path: String, at p: CGPoint) {
        guard let w = topWindow(at: p) else { return }
        uploadFile(path, to: w, at: localPoint(p, in: w))
    }
    #endif

    private func magnifyPointer() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { cursor.magnify = 3.5 }
        shakeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in withAnimation(.easeOut(duration: 0.4)) { self?.cursor.magnify = 1 } }
        shakeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// Puts a window in a part of the screen (for code outside this file).
    func snapWindow(_ w: DeskWindow, _ s: Snap) { snap(w, s) }

    // MARK: Apps installed from IPA files

    /// Loads the guest app into the process (first time) and puts its window on the desktop.
    func openApp(_ app: GuestApp) {
        guard isExternalConnected else {
            notice = String(localized: "Connect an external display first; the app opens as a window on the desktop.")
            return
        }
        if let w = windows.first(where: { $0.guestApp == app }) { focus(w); return }
        guard canOpenAnother(), let scene = PhoneWindow.current?.windowScene else { return }

        CrashReporter.setGuestName(app.name)
        do {
            try GuestStore.shared.prepareForLaunch(app)
        } catch {
            notice = error.localizedDescription
            return
        }
        do {
            let guest = try GuestRuntime.launchBundle(atPath: app.bundleURL.path, scene: scene)
            GuestRuntime.resumeApp(with: guest)        // reopened after its window was closed
            let area = desktopArea
            // Default size matches a phone screen, since iPhone apps are designed for it.
            let size = CGSize(width: min(430, area.width - 16),
                              height: min(800 + Layout.titleBar, area.height - 16))
            let step = CGFloat(windows.count % 8) * 32
            let origin = CGPoint(x: min(max(8, area.width - size.width - 48 - step), area.width - size.width),
                                 y: max(8, min(24 + step, area.height - size.height)))
            // Where the user left this app's window last time, if it still fits.
            let frame = rememberedFrame(of: app) ?? CGRect(origin: origin, size: size)
            let w = DeskWindow(app: app, window: guest, frame: frame)
            add(w)
            focusedID = w.id
            // Still running after 15 s: the app works in iDesk and may reopen by itself next time.
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self, weak w] in
                guard let self, w != nil else { return }
                var list = self.workedApps
                if !list.contains(app.id) { list.append(app.id); UserDefaults.standard.set(list, forKey: Keys.workedApps) }
            }
        } catch {
            notice = LaunchDiagnostics.explain(error.localizedDescription)
        }
        // Guest apps tend to grab the key window: give the keyboard back to iDesk.
        PhoneWindow.current?.makeKey()
        PhoneWindow.current?.claimKeyboard()
    }

    /// Whether one more window fits under the limit. If not, says so and opens Recent apps to close one.
    private func canOpenAnother() -> Bool {
        if maxWindows < 0 {
            // Automatic: open while memory lasts; stop before iOS would close iDesk (with every app inside it).
            switch MemoryStatus.level {
            case .fine:
                return true
            case .low:
                showToast(String(localized: "Memory is getting low (\(MemoryStatus.format(MemoryStatus.available)) left). Closing a window or two keeps APLite smooth."))
                return true
            case .critical:
                showToast(String(localized: "Memory is almost full (\(MemoryStatus.format(MemoryStatus.available)) left). Close a window to open another."))
                if recents == nil { showRecents() }
                return false
            }
        }
        guard maxWindows > 0, windows.count >= maxWindows else { return true }
        showToast(String(localized: "Up to \(maxWindows) windows can be open at once, so APLite stays smooth. Close one to open another."))
        if recents == nil { showRecents() }
        return false
    }

    func showToast(_ text: String) {
        toast = text
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    /// Each app's window comes back where it was and at the size it had.
    private func rememberFrame(of w: DeskWindow) {
        guard let app = w.guestApp else { return }
        let current = w.fullscreenRestore?.frame ?? w.frame
        let f = (w.isMaximized || w.isSnapped) ? (w.restoreFrame ?? current) : current
        var frames = UserDefaults.standard.dictionary(forKey: Keys.appFrames) as? [String: String] ?? [:]
        frames[app.id] = NSCoder.string(for: f)
        UserDefaults.standard.set(frames, forKey: Keys.appFrames)
    }

    private func rememberedFrame(of app: GuestApp) -> CGRect? {
        guard let s = (UserDefaults.standard.dictionary(forKey: Keys.appFrames) as? [String: String])?[app.id] else { return nil }
        let f = NSCoder.cgRect(for: s), area = desktopArea
        guard f.width >= Layout.minWindowSize.width, f.height >= Layout.minWindowSize.height,
              f.width <= area.width, f.height <= area.height else { return nil }
        return CGRect(x: min(max(area.minX, f.minX), area.maxX - f.width),
                      y: min(max(area.minY, f.minY), area.maxY - f.height), width: f.width, height: f.height)
    }

    private func add(_ w: DeskWindow) {
        w.workspace = workspace
        w.onChange = { [weak self] in self?.scheduleSave() }
        w.onCloseRequest = { [weak self, weak w] in if let self, let w { self.close(w) } }
        w.onFullscreen = { [weak self, weak w] on in
            guard let self, let w else { return }
            self.setFullscreen(w, on)
        }
        // Spring the new window in: it grows from the dock/taskbar click instead of blinking in.
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { windows.append(w) }
        restack()
        scheduleSave()
    }

    func focus(_ w: DeskWindow) {
        if w.workspace != workspace { setWorkspace(w.workspace) }
        w.isMinimized = false
        if let i = windows.firstIndex(where: { $0.id == w.id }), i != windows.count - 1 {
            windows.append(windows.remove(at: i))
        }
        restack()
        focusedID = w.id
    }

    /// Windows kept on top stay above the others, whichever is focused.
    private func restack() {
        guard windows.contains(where: \.keepOnTop) else { return }
        let ordered = windows.filter { !$0.keepOnTop } + windows.filter(\.keepOnTop)
        if ordered.map(\.id) != windows.map(\.id) { windows = ordered }
    }

    func toggleKeepOnTop(_ w: DeskWindow) {
        w.keepOnTop.toggle()
        restack()
        showToast(w.keepOnTop ? String(localized: "“\(w.title)” stays on top of other windows")
                              : String(localized: "“\(w.title)” no longer stays on top"))
    }

    /// Tabs and browser windows closed in this session, newest last: ⌘ + Shift + T brings them back.
    private enum Closed { case tab(URL, window: UUID), window([URL], frame: CGRect) }
    private var closed: [Closed] = []
    var canReopenClosed: Bool { !closed.isEmpty }

    private func remember(_ item: Closed) {
        closed.append(item)
        if closed.count > 25 { closed.removeFirst() }
    }

    /// ⌘ + Shift + T: the last closed tab goes back into its window (or the focused browser window), a closed
    /// window opens again with its tabs.
    func reopenClosed() {
        guard isExternalConnected, let item = closed.popLast() else { return }
        switch item {
        case let .tab(url, id):
            if let w = window(id) ?? windows.last(where: { $0.isBrowser && $0.isShown }) {
                w.newTab(url)
                focus(w)
                scheduleSave()
            } else {
                openWindow(url)
            }
        case let .window(urls, frame):
            guard let first = urls.first else { return }
            openWindow(first)
            guard let w = windows.last, w.isBrowser else { return }
            for url in urls.dropFirst() { w.newTab(url, activate: false) }
            if !w.isMaximized { w.frame = frame.intersection(desktopArea).isNull ? w.frame : frame }
            scheduleSave()
        }
    }

    func close(_ w: DeskWindow) {
        if w.isBrowser, !w.tabs.isEmpty { remember(.window(w.tabs.indices.map { w.url(ofTab: $0) }, frame: w.frame)) }
        rememberFrame(of: w)
        w.webView?.stopLoading()
        if w.isApp, isGuestDrag { Self.guestInput { GuestTouch.cancel() }; drag = .none }
        // Where its icon sits in the dock right now: the ghost window flies back there.
        let target = taskLayout.first(where: { $0.entry.window === w })?.rect
            ?? CGRect(x: screenSize.width / 2, y: screenSize.height - 30, width: 1, height: 1)
        closingWork?.cancel()
        let ghost = ClosingWindow(title: w.title, icon: w.icon, symbol: w.symbol, from: w.frame, to: target)
        closingWindow = ghost
        withAnimation(.easeIn(duration: 0.22)) { windows.removeAll { $0.id == w.id } }
        let cleanup = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.12)) { self?.closingWindow = nil }
        }
        closingWork = cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: cleanup)
        // Closing an app: it gets the "went to the background" events, so it stops playing and pauses.
        if let guest = w.guestWindow { GuestRuntime.suspendApp(with: guest) }
        focusedID = windows.last(where: { $0.isShown })?.id
        hoverInFlight = false
        scheduleSave()
    }

    func minimize(_ w: DeskWindow) {
        withAnimation(.easeInOut(duration: 0.2)) { w.isMinimized = true }
        if focusedID == w.id { focusedID = windows.last(where: { $0.isShown })?.id }
        scheduleSave()
    }

    /// The window covers the whole external display (taskbar included) when the page requests fullscreen.
    func setFullscreen(_ w: DeskWindow, _ on: Bool) {
        guard on != w.isFullscreen else { return }
        objectWillChange.send()   // the desktop must redraw to hide/show the taskbar
        if on {
            w.fullscreenRestore = (w.frame, w.isMaximized, w.isSnapped)
            w.isFullscreen = true
            w.frame = CGRect(origin: .zero, size: screenSize)
            showLauncher = false
            contextMenu = nil
            focus(w)
        } else {
            w.isFullscreen = false
            if let r = w.fullscreenRestore {
                w.frame = r.frame
                w.isMaximized = r.maximized
                w.isSnapped = r.snapped
            }
            w.fullscreenRestore = nil
            w.fullscreenFrame = nil
        }
        updateHover(cursor.position)
    }

    /// Whether any window is fullscreen (the taskbar is hidden).
    var hasFullscreen: Bool { windows.contains { $0.isFullscreen && $0.isShown } }

    /// Top edge of the taskbar's hit area; none while a window is fullscreen and the taskbar is hidden.
    private var taskbarHitTop: CGFloat { taskbarVisible ? taskbarTop : .infinity }

    /// Hidden while a window is fullscreen; with auto-hide, shown only when the pointer is at the bottom edge or
    /// something that belongs to it is open.
    var taskbarVisible: Bool {
        !hasFullscreen && (!autoHideTaskbar || taskbarRevealed || showLauncher || showQuickPanel || recents != nil
                           || contextMenu != nil)
    }

    private func updateTaskbarReveal(_ p: CGPoint) {
        guard autoHideTaskbar else { return }
        let reveal = taskbarRevealed ? p.y >= taskbarTop - 8 : p.y >= screenSize.height - 3
        if reveal != taskbarRevealed { withAnimation(.easeOut(duration: 0.18)) { taskbarRevealed = reveal } }
    }

    func toggleMaximize(_ w: DeskWindow) {
        if w.isMaximized {
            w.frame = w.restoreFrame ?? w.frame
            w.isMaximized = false
        } else {
            if !w.isSnapped { w.restoreFrame = w.frame }
            w.frame = maximizedFrame
            w.isMaximized = true
        }
        w.isSnapped = false
        w.snap = nil
        scheduleSave()
    }

    private func snap(_ w: DeskWindow, _ s: Snap) {
        if s == .maximize {
            if !w.isMaximized { toggleMaximize(w) }
            return
        }
        if !w.isMaximized && !w.isSnapped { w.restoreFrame = w.frame }
        w.frame = snapRect(s)
        w.isMaximized = false
        w.isSnapped = true
        w.snap = s
        scheduleSave()
    }

    /// Restores a maximized or snapped window to its size before.
    private func restore(_ w: DeskWindow) {
        if w.isMaximized { toggleMaximize(w); return }
        guard w.isSnapped else { return }
        if let r = w.restoreFrame { w.frame = r }
        w.isSnapped = false
        w.snap = nil
        scheduleSave()
    }

    enum Direction { case left, right, up, down }

    /// ⌘ + arrow keys, as on a computer: halves left / right, then quarters with up / down;
    /// up maximizes, down restores and then minimizes.
    func snapFocused(_ direction: Direction) {
        guard let w = focused, !w.isMinimized, !w.isFullscreen else { return }
        let current = w.isSnapped ? w.snap : (w.isMaximized ? .maximize : nil)
        switch (direction, current) {
        case (.left, .right), (.right, .left): restore(w)
        case (.left, .topRight), (.left, .bottomRight), (.right, .topLeft), (.right, .bottomLeft):
            restore(w)
        case (.left, _): snap(w, .left)
        case (.right, _): snap(w, .right)
        case (.up, .left), (.up, .bottomLeft): snap(w, .topLeft)
        case (.up, .right), (.up, .bottomRight): snap(w, .topRight)
        case (.up, _): snap(w, .maximize)
        case (.down, .left), (.down, .topLeft): snap(w, .bottomLeft)
        case (.down, .right), (.down, .topRight): snap(w, .bottomRight)
        case (.down, .maximize): restore(w)
        case (.down, _): if w.isSnapped { restore(w) } else { minimize(w) }
        }
        if w.isSnapped, let s = w.snap { suggestFill(after: w, s) } else { fillSuggestion = nil }
    }

    private func snapRect(_ s: Snap) -> CGRect {
        let a = maximizedFrame
        switch s {
        case .maximize: return a
        case .left: return CGRect(x: a.minX, y: a.minY, width: a.width / 2 - 3, height: a.height)
        case .right: return CGRect(x: a.midX + 3, y: a.minY, width: a.width / 2 - 3, height: a.height)
        case .topLeft: return CGRect(x: a.minX, y: a.minY, width: a.width / 2 - 3, height: a.height / 2 - 3)
        case .topRight: return CGRect(x: a.midX + 3, y: a.minY, width: a.width / 2 - 3, height: a.height / 2 - 3)
        case .bottomLeft: return CGRect(x: a.minX, y: a.midY + 3, width: a.width / 2 - 3, height: a.height / 2 - 3)
        case .bottomRight: return CGRect(x: a.midX + 3, y: a.midY + 3, width: a.width / 2 - 3, height: a.height / 2 - 3)
        case .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds:
            let gap: CGFloat = 6, third = (a.width - gap * 2) / 3
            let start: CGFloat = s == .centerThird || s == .rightTwoThirds ? 1 : s == .rightThird ? 2 : 0
            let span: CGFloat = s == .leftTwoThirds || s == .rightTwoThirds ? 2 : 1
            return CGRect(x: a.minX + start * (third + gap), y: a.minY, width: span * third + (span - 1) * gap, height: a.height)
        }
    }

    /// Arranges visible windows in a grid.
    func tileWindows() {
        let visible = windows.filter { $0.isShown }
        guard !visible.isEmpty else { return }
        let cols = Int(ceil(Double(visible.count).squareRoot()))
        let rows = Int(ceil(Double(visible.count) / Double(cols)))
        let a = maximizedFrame, gap: CGFloat = 6
        let cw = (a.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let ch = (a.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        for (i, w) in visible.enumerated() {
            let c = i % cols, r = i / cols
            w.frame = CGRect(x: a.minX + CGFloat(c) * (cw + gap), y: a.minY + CGFloat(r) * (ch + gap), width: cw, height: ch)
            w.isMaximized = false
            w.isSnapped = false
        }
        scheduleSave()
    }

    /// Cascades windows.
    func cascadeWindows() {
        let a = desktopArea
        let size = CGSize(width: min(1000, a.width * 0.6), height: min(700, a.height * 0.7))
        for (i, w) in windows.filter({ $0.isShown }).enumerated() {
            let step = CGFloat(i % 10) * 36
            w.frame = CGRect(origin: CGPoint(x: a.minX + 24 + step, y: a.minY + 24 + step), size: size)
            w.isMaximized = false
            w.isSnapped = false
        }
        scheduleSave()
    }

    /// "Show desktop" button: minimize everything, press again to restore.
    func toggleShowDesktop() {
        let visible = windows.filter { $0.isShown }
        if visible.isEmpty {
            for id in hiddenByShowDesktop { if let w = window(id), w.workspace == workspace { w.isMinimized = false } }
            hiddenByShowDesktop = []
            focusedID = windows.last(where: { $0.isShown })?.id
        } else {
            hiddenByShowDesktop = visible.map(\.id)
            visible.forEach { $0.isMinimized = true }
            focusedID = nil
        }
        scheduleSave()
    }

    // MARK: Workspaces

    /// The windows of the workspace shown, in stacking order.
    var deskWindows: [DeskWindow] { windows.filter { $0.workspace == workspace } }

    func setWorkspace(_ n: Int) {
        guard (0..<Self.workspaceCount).contains(n), n != workspace else { return }
        if isGuestDrag { Self.guestInput { GuestTouch.cancel() } }
        drag = .none
        contextMenu = nil
        showLauncher = false
        closeRecents()
        hiddenByShowDesktop = []
        workspace = n
        if let w = workspaceWallpapers[String(n)], w != wallpaper { wallpaper = w }
        for w in windows { w.isOffDesk = w.workspace != n }
        focusedID = windows.last(where: { $0.isShown })?.id
        showToast(String(localized: "Workspace \(n + 1)"))
        updateHover(cursor.position)
        scheduleSave()
    }

    /// ⌘ + Ctrl+← / →, four-finger swipe: the previous / next workspace (wraps around).
    func switchWorkspace(by step: Int) {
        guard isExternalConnected, workspacesEnabled else { return }
        setWorkspace((workspace + step + Self.workspaceCount) % Self.workspaceCount)
    }

    func move(_ w: DeskWindow, toWorkspace n: Int) {
        guard (0..<Self.workspaceCount).contains(n), n != w.workspace else { return }
        w.workspace = n
        w.isOffDesk = n != workspace
        if focusedID == w.id, w.isOffDesk { focusedID = windows.last(where: { $0.isShown })?.id }
        showToast(String(localized: "Moved to workspace \(n + 1)"))
        scheduleSave()
    }

    /// ⌘ + Ctrl+Shift+← / →: the focused window goes to the previous / next workspace, and the desktop follows it.
    func moveFocusedToWorkspace(by step: Int) {
        guard workspacesEnabled, let w = focused else { return }
        w.workspace = (w.workspace + step + Self.workspaceCount) % Self.workspaceCount
        focus(w)
    }

    /// Three-finger swipe left / right: the next / previous app of this workspace, like swiping along the iPhone's
    /// home bar.
    func switchApp(forward: Bool) {
        let list = deskWindows
        guard list.count > 1 else { return }
        closeRecents()
        showLauncher = false
        focus(forward ? list[0] : list[list.count - 2])
    }

    func workspaceCellRect(_ n: Int) -> CGRect {
        let first = navButtonRect(.back).maxX + 8
        return CGRect(x: first + CGFloat(n) * Layout.workspaceCell, y: dockY + (dockHeight - 30) / 2,
                      width: Layout.workspaceCell, height: 30)
    }

    func nextWallpaper() {
        // Gradients, then the dynamic one, then back to the first.
        wallpaper = wallpaper == DynamicWallpaper.index ? 0 : wallpaper < 0 ? 0
            : wallpaper + 1 < Wallpapers.count ? wallpaper + 1 : DynamicWallpaper.index
    }

    private static var wallpaperFile: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("iDeskWallpaper.jpg")
    }

    /// Sets a photo as wallpaper: scaled down to display size (less memory), then saved.
    func setCustomWallpaper(_ data: Data) {
        guard let image = UIImage(data: data) else { notice = String(localized: "Could not read this image."); return }
        applyCustomWallpaper(image)
    }

    /// Picks a picture from Files. The document picker copies it into the app's temporary folder,
    /// so the URL needs no security-scoped access; other callers may pass one anyway.
    func setCustomWallpaper(contentsOf url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
            notice = String(localized: "Could not read this image.")
            return
        }
        applyCustomWallpaper(image)
    }

    private func applyCustomWallpaper(_ image: UIImage) {
        let maxSide: CGFloat = 2560
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        try? resized.jpegData(compressionQuality: 0.85)?.write(to: Self.wallpaperFile, options: .atomic)
        customWallpaper = resized
        wallpaper = -1
    }

    func topWindow(at p: CGPoint) -> DeskWindow? {
        windows.reversed().first { $0.isShown && $0.frame.contains(p) }
    }

    /// Like topWindow but includes the outer border, to catch resize edges.
    private func pointerWindow(at p: CGPoint) -> DeskWindow? {
        let g = Layout.edgeGrab
        return windows.reversed().first { $0.isShown && $0.frame.insetBy(dx: -g, dy: -g).contains(p) }
    }

    private func resizeEdges(_ w: DeskWindow, at p: CGPoint) -> ResizeEdges {
        guard !w.isMaximized, !w.isFullscreen else { return [] }
        let f = w.frame, g = Layout.edgeGrab
        guard f.insetBy(dx: -g, dy: -g).contains(p) else { return [] }
        if p.x > f.maxX - Layout.resizeGrip && p.y > f.maxY - Layout.resizeGrip { return [.right, .bottom] }
        var e: ResizeEdges = []
        if p.x < f.minX + g { e.insert(.left) }
        if p.x > f.maxX - g { e.insert(.right) }
        if p.y < f.minY + 3 { e.insert(.top) }
        if p.y > f.maxY - g { e.insert(.bottom) }
        return e
    }

    private func isOverContent(_ p: CGPoint, of w: DeskWindow) -> Bool {
        w.frame.contains(p) && p.y >= w.frame.minY + w.chromeHeight
    }

    // MARK: Taskbar / app menu / icon geometry

    /// Height of the floating dock and its top edge inside the taskbar band.
    var dockHeight: CGFloat { min(56, max(42, 52 * CGFloat(dockScale))) }
    var dockY: CGFloat { taskbarTop + (Layout.taskbar - dockHeight) / 2 }
    private var dockControlY: CGFloat { dockY + (dockHeight - Layout.buttonHeight) / 2 }

    var startButtonRect: CGRect {
        CGRect(x: Layout.dockMargin + Layout.dockPadding, y: dockControlY,
               width: Layout.startWidth, height: Layout.buttonHeight)
    }

    func navButtonRect(_ b: NavButton) -> CGRect {
        let i = CGFloat(NavButton.allCases.firstIndex(of: b)!)
        let x = startButtonRect.maxX + 6 + i * (Layout.navWidth + Layout.navGap)
        return CGRect(x: x, y: dockControlY, width: Layout.navWidth, height: Layout.buttonHeight)
    }

    /// The left glass pill: app menu, Spotlight, Recent apps, Home, Back and (optionally) workspaces.
    var leftDockRect: CGRect {
        let end = workspacesEnabled ? workspaceCellRect(Self.workspaceCount - 1).maxX : navButtonRect(.back).maxX
        let x = Layout.dockMargin
        return CGRect(x: x, y: dockY, width: end + Layout.dockPadding - x, height: dockHeight)
    }

    var showDesktopRect: CGRect {
        CGRect(x: screenSize.width - Layout.dockMargin - Layout.dockPadding - Layout.showDesktopWidth,
               y: dockY, width: Layout.showDesktopWidth, height: dockHeight)
    }

    var taskManagerButtonRect: CGRect {
        let h = min(38, dockHeight - 10)
        return CGRect(x: showDesktopRect.minX - Layout.trayWidth - 40, y: dockY + (dockHeight - h) / 2,
                      width: 36, height: h)
    }

    var trayRect: CGRect {
        CGRect(x: showDesktopRect.minX - Layout.trayWidth, y: dockY,
               width: Layout.trayWidth, height: dockHeight)
    }

    /// The right glass pill: recording / downloads when shown, the system tray and Show desktop.
    var rightDockRect: CGRect {
        let left = (recordButtonRect?.minX ?? downloadsButtonRect?.minX ?? taskManagerButtonRect.minX) - Layout.dockPadding
        return CGRect(x: left, y: dockY, width: screenSize.width - Layout.dockMargin - left, height: dockHeight)
    }

    /// Dock entries and where they are. App icons sit in a centred glass pill between the two side
    /// pills; with too many windows the icons shrink, then the ones that still do not fit are left
    /// out (Recent apps and ⌘Tab reach them) rather than running under the tray.
    var taskLayout: [(entry: TaskEntry, rect: CGRect)] {
        let entries = taskEntries
        guard !entries.isEmpty else { return [] }
        let gap = CGFloat(dockSpacing)
        let n = CGFloat(entries.count)
        let available = max(0, rightDockRect.minX - leftDockRect.maxX - Layout.dockGap * 2 - Layout.dockPadding * 2)
        let base = min(Layout.dockItemMax, max(Layout.dockItemMin, Layout.dockIconBase * CGFloat(dockIconScale)))
        var side = (available - gap * (n - 1)) / n
        side = max(Layout.dockItemMin, min(base, side))
        let total = n * side + (n - 1) * gap
        let minX = leftDockRect.maxX + Layout.dockGap + Layout.dockPadding
        let maxX = rightDockRect.minX - Layout.dockGap - Layout.dockPadding
        let startX = min(max(minX, (screenSize.width - total) / 2), max(minX, maxX - total))
        var x = startX
        return entries.compactMap { entry in
            guard x + side <= maxX + 0.5 else { return nil }
            defer { x += side + gap }
            return (entry, CGRect(x: x, y: dockY + (dockHeight - side) / 2, width: side, height: side))
        }
    }

    /// The centred glass pill around the app icons (zero when there are no entries).
    var dockRect: CGRect {
        let items = taskLayout
        guard let first = items.first, let last = items.last else { return .zero }
        return CGRect(x: first.rect.minX - Layout.dockPadding, y: dockY,
                      width: last.rect.maxX - first.rect.minX + Layout.dockPadding * 2, height: dockHeight)
    }

    var launcherRect: CGRect {
        let cols = Layout.launcherColumns, recents = launcherRecents.count, count = launcherItems.count
        // With a Recent row: that row, then the apps from a new row, each under its own title.
        let rows = CGFloat(max(1, recents > 0 ? 1 + (count - recents + cols - 1) / cols : (count + cols - 1) / cols))
        let t = Layout.launcherTile, g = Layout.launcherGap, pad = Layout.launcherPadding
        let w = pad * 2 + CGFloat(cols) * t.width + CGFloat(cols - 1) * g
        let titles = recents > 0 ? Layout.launcherSectionTitle * 2 : 0
        let footer = launcherShowsAppsHint ? Layout.launcherFooter : 0
        let h = pad * 2 + Layout.launcherHeader + titles + rows * t.height + max(0, rows - 1) * g + footer
        return CGRect(x: 8, y: max(8, taskbarTop - h - 8), width: w, height: h)
    }

    func launcherItemRect(_ i: Int) -> CGRect {
        let r = launcherRect, t = Layout.launcherTile, g = Layout.launcherGap, pad = Layout.launcherPadding
        let cols = Layout.launcherColumns, recents = launcherRecents.count
        var row = i / cols, col = i % cols, titles: CGFloat = 0
        if recents > 0 {
            titles = Layout.launcherSectionTitle
            if i < recents { row = 0; col = i }
            else { row = 1 + (i - recents) / cols; col = (i - recents) % cols; titles += Layout.launcherSectionTitle }
        }
        return CGRect(x: r.minX + pad + CGFloat(col) * (t.width + g),
                      y: r.minY + pad + Layout.launcherHeader + titles + CGFloat(row) * (t.height + g),
                      width: t.width, height: t.height)
    }

    func iconRect(_ i: Int) -> CGRect {
        let c = Layout.iconCell, g = Layout.iconGap, o = Layout.iconOrigin
        let col = CGFloat(i / 1000), row = CGFloat(i % 1000)
        return CGRect(x: o.x + col * (c.width + g), y: o.y + row * (c.height + g), width: c.width, height: c.height)
    }

    // MARK: Pointer & mouse

    func moveCursor(dx: CGFloat, dy: CGFloat) {
        var p = cursor.position
        p.x = min(max(0, p.x + dx), screenSize.width - 1)
        p.y = min(max(0, p.y + dy), screenSize.height - 1)
        cursor.position = p
        if showScreenSaver, hypot(dx, dy) > 3 { noteInput() } else if !isLocked { lastInput = Date() }
        if isLocked { return }

        // Screenshot of an area: the pointer drags it out.
        if var c = capture {
            if let s = c.start {
                c.rect = CGRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))
                capture = c
            }
            return
        }

        switch drag {
        case .none:
            updateTaskbarReveal(p)
            updateHover(p)
            checkHotCorner(p)
            if shake.feed(dx: dx) { magnifyPointer() }
        case let .move(id, offset):
            guard let w = window(id) else { return }
            // Some of the title bar always stays on screen, so the window can be dragged back.
            let keep: CGFloat = 120
            w.frame.origin = CGPoint(x: min(max(p.x - offset.x, keep - w.frame.width), screenSize.width - keep),
                                     y: max(0, min(p.y - offset.y, taskbarTop - Layout.titleBar)))
            // Dragged to the left/right edge: half the screen; near a corner of it: a quarter.
            // To the top edge: maximize.
            let top = p.y < desktopArea.height * 0.2, bottom = p.y > desktopArea.height * 0.8
            let edge: CGFloat = 6       // the pointer stops at the screen edge; a touch in preview mode lands near it
            // At the top edge the layouts show; the pointer then moves down onto one of their zones.
            if p.y <= edge, !showTilePicker { withAnimation(.easeOut(duration: 0.15)) { showTilePicker = true } }
            let zone = showTilePicker ? tileZone(at: p) : nil
            if zone != tileHover { tileHover = zone }
            if let zone { snapTarget = zone.snap }
            else if p.x <= edge { snapTarget = top ? .topLeft : bottom ? .bottomLeft : .left }
            else if p.x >= screenSize.width - 1 - edge { snapTarget = top ? .topRight : bottom ? .bottomRight : .right }
            else if p.y <= edge { snapTarget = .maximize }
            else { snapTarget = nil }
            if showTilePicker, p.y > edge, !tilePickerRect.insetBy(dx: -40, dy: -60).contains(p) {
                withAnimation(.easeOut(duration: 0.15)) { showTilePicker = false }
            }
            let preview = snapTarget.map(snapRect)
            if preview != snapPreview { snapPreview = preview }
        case let .resize(id, edges, start, sf):
            guard let w = window(id) else { return }
            let dx = p.x - start.x, dy = p.y - start.y
            let minW = Layout.minWindowSize.width, minH = Layout.minWindowSize.height
            var f = sf
            if edges.contains(.right) { f.size.width = max(minW, sf.width + dx) }
            if edges.contains(.left) {
                let nw = max(minW, sf.width - dx)
                f.origin.x = sf.maxX - nw
                f.size.width = nw
            }
            if edges.contains(.bottom) { f.size.height = max(minH, sf.height + dy) }
            if edges.contains(.top) {
                let nh = max(minH, sf.height - dy)
                f.origin.y = max(0, sf.maxY - nh)
                f.size.height = sf.maxY - f.origin.y
            }
            w.frame = f
        case let .guest(id):
            guard let w = window(id) else { return }
            let local = localPoint(p, in: w)
            Self.guestInput { GuestTouch.move(to: local) }
        case let .icon(item, from):
            if iconDrag == nil, hypot(p.x - from.x, p.y - from.y) > 6 {
                iconDrag = item
                if showLauncher { showLauncher = false }      // the desktop shows, to drop the app on it
                cursor.setStyle(.grab)
            }
            if iconDrag != nil {
                let slot = dropSlot(at: p)
                if slot != iconDropSlot { iconDropSlot = slot }
            }
        case .filePending:
            break
        case let .widget(kind, offset):
            WidgetStore.shared.positions[kind] = CGPoint(x: p.x - offset.x, y: p.y - offset.y)
            objectWillChange.send()
        case let .sticky(id, offset):
            guard let i = stickies.firstIndex(where: { $0.id == id }) else { return }
            stickies[i].x = Double(min(max(0, p.x - offset.x), screenSize.width - 60))
            stickies[i].y = Double(min(max(0, p.y - offset.y), taskbarTop - StickyNote.header))
        }
    }

    /// Updates the pointer shape and sends hover events to the page under the pointer.
    private func updateHover(_ p: CGPoint) {
        updateTaskPreview(p)
        if quickLook != nil || contextMenu != nil || recents != nil || (showLauncher && launcherRect.contains(p)) || p.y >= taskbarHitTop
            || showSpotlight || showClipboard || showEmoji || (showDownloads && downloadsRect.contains(p)) || fillSuggestion.map({ fillArea($0).contains(p) }) == true
            || stickyIndex(at: p) != nil
            || (showQuickPanel && quickPanelRect.contains(p)) || (banner != nil && bannerRect.contains(p)) {
            cursor.setStyle(.arrow); return
        }
        guard let w = pointerWindow(at: p) else { cursor.setStyle(.arrow); return }
        let edges = resizeEdges(w, at: p)
        if !edges.isEmpty { cursor.setStyle(edges.cursorStyle); return }
        guard isOverContent(p, of: w), let web = w.webView else { cursor.setStyle(.arrow); return }

        let now = CACurrentMediaTime()
        if hoverInFlight && now - hoverStarted < 0.5 { hoverAgain = true; return }
        hoverInFlight = true
        hoverStarted = now
        WebInput.hover(web, at: localPoint(p, in: w)) { [weak self, weak w] style in
            guard let self else { return }
            self.hoverInFlight = false
            if case .none = self.drag, self.contextMenu == nil, let w,
               self.topWindow(at: self.cursor.position) === w, self.isOverContent(self.cursor.position, of: w) {
                self.cursor.setStyle(style)
            }
            if self.hoverAgain {
                self.hoverAgain = false
                if case .none = self.drag { self.updateHover(self.cursor.position) }
            }
        }
    }

    /// Hovering a window's button on the dock for a moment shows a picture of the window above it.
    /// The dock geometry is only computed when the pointer is actually in the taskbar band: this
    /// runs on every pointer move, and taskLayout walks every pinned app and open window.
    private func updateTaskPreview(_ p: CGPoint) {
        guard p.y >= taskbarHitTop, contextMenu == nil, recents == nil, !showLauncher else {
            cancelTaskPreview()
            return
        }
        let items = taskLayout
        guard let item = items.first(where: { $0.rect.contains(p) && $0.entry.window != nil }),
              let w = item.entry.window else {
            cancelTaskPreview()
            return
        }
        if taskPreview?.id == w.id { return }
        cancelTaskPreview()
        let anchor = item.rect
        let work = DispatchWorkItem { [weak self, weak w] in
            guard let self, let w else { return }
            self.thumbnail(of: w) { [weak self] image in
                guard let self, self.cursor.position.y >= self.taskbarHitTop,
                      self.taskLayout.first(where: { $0.rect.contains(self.cursor.position) })?.entry.window === w
                else { return }
                self.taskPreview = TaskPreview(id: w.id, title: w.title, image: image, anchor: anchor)
            }
        }
        taskPreviewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func cancelTaskPreview() {
        taskPreviewWork?.cancel()
        taskPreviewWork = nil
        if taskPreview != nil { taskPreview = nil }
    }

    /// Press (start of a drag): drag the title bar to move, an edge/corner to resize.
    func mouseDown() {
        if isLocked || showScreenSaver { noteInput(); return }
        cursor.isPressed = true
        let p = cursor.position
        if capture != nil { capture = CaptureState(start: p, rect: CGRect(origin: p, size: .zero)); return }
        if showSpotlight || showClipboard { return }
        if let f = fillSuggestion, !fillArea(f).contains(p) { fillSuggestion = nil }
        // A widget (not on the timer's buttons): dragging moves it.
        if p.y < taskbarHitTop, pointerWindow(at: p) == nil, stickyIndex(at: p) == nil, let k = widget(at: p),
           !(k == .pomodoro && (pomodoroButtonRect(0).contains(p) || pomodoroButtonRect(1).contains(p))) {
            let r = widgetRect(k)
            drag = .widget(k, offset: CGPoint(x: p.x - r.minX, y: p.y - r.minY))
            cursor.setStyle(.grab)
            return
        }
        // A sticky note's top strip: dragging moves it.
        if let i = stickyIndex(at: p),
           p.y < stickies[i].frame.minY + StickyNote.header, !stickyCloseRect(stickies[i]).contains(p) {
            let note = stickies.remove(at: i)
            stickies.append(note)
            drag = .sticky(note.id, offset: CGPoint(x: p.x - note.frame.minX, y: p.y - note.frame.minY))
            cursor.setStyle(.grab)
            return
        }
        if quickLook != nil || contextMenu != nil || recents != nil || (showQuickPanel && quickPanelRect.contains(p)) { return }
        // An app in the app menu: dragging it puts it on the desktop.
        if showLauncher, launcherRect.contains(p) {
            let all = launcherItems
            if let i = all.indices.first(where: { launcherItemRect($0).contains(p) }) { drag = .icon(all[i], from: p) }
            return
        }
        // An icon on the desktop: dragging it moves it.
        if p.y < taskbarHitTop, pointerWindow(at: p) == nil, let hit = desktopIcon(at: p) {
            drag = .icon(hit.item, from: p)
            return
        }
        guard p.y < taskbarHitTop, let w = pointerWindow(at: p) else { return }
        focus(w)
        let edges = resizeEdges(w, at: p)
        if !edges.isEmpty {
            w.isMaximized = false
            w.isSnapped = false
            drag = .resize(w.id, edges: edges, start: p, startFrame: w.frame)
            cursor.setStyle(edges.cursorStyle)
        } else if w.frame.contains(p), !w.isFullscreen, p.y < w.frame.minY + Layout.titleBar,
                  !Layout.titleButtons(in: w.frame).contains(p) {
            if w.isMaximized || w.isSnapped, let r = w.restoreFrame {
                // Dragging a maximized/snapped window: restore its size, keeping the pointer at the same spot on the title bar.
                let rx = (p.x - w.frame.minX) / max(1, w.frame.width)
                w.isMaximized = false
                w.isSnapped = false
                w.frame = CGRect(x: p.x - r.width * rx, y: w.frame.minY, width: r.width, height: r.height)
            }
            drag = .move(w.id, offset: CGPoint(x: p.x - w.frame.minX, y: p.y - w.frame.minY))
            cursor.setStyle(.grab)
        } else if w.systemPage == .files, let web = w.webView, isOverContent(p, of: w) {
            // A file in Files: dragging it to the desktop puts a shortcut there. Ask the page which file it is.
            drag = .filePending(from: p)
            WebInput.fileName(web, at: localPoint(p, in: w)) { [weak self] path in
                guard let self, let path, let url = FileStore.resolve(path), case .filePending = self.drag else { return }
                let symbol = FileStore.isFolder(url) ? "folder.fill" : FileStore.iconSymbol(for: url.pathExtension)
                self.drag = .icon(Shortcut(name: url.lastPathComponent, symbol: symbol,
                                           url: url.absoluteString, hue: 0.6, file: path), from: p)
                self.moveCursor(dx: 0, dy: 0)
            }
        } else if let guest = w.guestWindow, isOverContent(p, of: w) {
            // Press and drag in a guest app = put a finger down and move it (sliders, swipes…).
            let local = localPoint(p, in: w)
            Self.guestInput { Self.touchDown(at: local, in: guest) }
            drag = .guest(w.id)
        }
    }

    func mouseUp() {
        cursor.isPressed = false
        if let c = capture, c.start != nil {
            // A real area: captured. A press without moving: click() captures the window under the pointer.
            if let r = c.rect, r.width > 8, r.height > 8 { finishCapture(r) } else { capture = CaptureState() }
            return
        }
        let wasDragging = isDragging
        if isGuestDrag { Self.guestInput { GuestTouch.end() } }
        if showTilePicker || tileHover != nil { withAnimation(.easeOut(duration: 0.15)) { showTilePicker = false }; tileHover = nil }
        if case let .move(id, _) = drag, let s = snapTarget, let w = window(id) {
            snap(w, s)
            suggestFill(after: w, s)
        }
        if case let .icon(item, _) = drag, iconDrag != nil {
            if let path = item.file, let w = topWindow(at: cursor.position), w.webView != nil, w.systemPage == nil {
                uploadFile(path, to: w, at: localPoint(cursor.position, in: w))
            } else if let slot = iconDropSlot { dropOnDesktop(item, slot: slot) }
            iconDrag = nil
            iconDropSlot = nil
        }
        if case .widget = drag { WidgetStore.shared.savePositions() }
        drag = .none
        snapTarget = nil
        snapPreview = nil
        if wasDragging {
            scheduleSave()
            updateHover(cursor.position)
        }
    }

    // Real mouse (GCMouse): press and release in place = click; press and move = drag.
    func physicalPress() {
        pressPoint = cursor.position
        mouseDown()
    }

    func physicalRelease() {
        let moved = pressPoint.map { hypot($0.x - cursor.position.x, $0.y - cursor.position.y) > 4 } ?? true
        let wasGuest = isGuestDrag      // the guest app already received the whole touch (down + up)
        mouseUp()
        if !moved && !wasGuest { click() }
        pressPoint = nil
    }

    func click() {
        if isLocked { return }
        if showScreenSaver { noteInput(); return }
        noteInput()
        let p = cursor.position
        flashPress()
        Self.typingTargetChanged()        // a click may put the caret in another field
        if capture != nil {
            finishCapture(topWindow(at: p)?.frame ?? CGRect(origin: .zero, size: screenSize))
            return
        }
        if editingSticky != nil, stickyIndex(at: p) == nil { editingSticky = nil }
        let now = CACurrentMediaTime()
        let isDouble = now - lastClickTime < 0.45 && hypot(p.x - lastClickPoint.x, p.y - lastClickPoint.y) < 10
        lastClickTime = isDouble ? 0 : now
        lastClickPoint = p

        if let menu = contextMenu {
            contextMenu = nil
            if let i = menu.items.indices.first(where: { menu.itemRect($0).contains(p) }),
               menu.items[i].enabled, let action = menu.items[i].action {
                action()
            }
            return
        }

        if quickLook != nil {
            if !quickLookRect.contains(p) { quickLook = nil }
            return
        }
        if let shot = screenshotPreview, screenshotPreviewRect.contains(p) {
            screenshotPreview = nil
            if let url = FileStore.resolve(shot.path) { quickLook = url }
            return
        }
        if showSpotlight { clickSpotlight(at: p); return }
        if showClipboard { clickClipboard(at: p); return }
        if showDownloads { clickDownloads(at: p); return }
        if showTaskManager { clickTaskManager(at: p); return }
        if showEmoji { clickEmoji(at: p); return }
        if let f = fillSuggestion {
            if let i = f.ids.indices.first(where: { fillCardRect($0, of: f).contains(p) }), let w = window(f.ids[i]) {
                fillSuggestion = nil
                focus(w)
                snap(w, f.zone)
                return
            }
            fillSuggestion = nil
            if fillArea(f).contains(p) { return }
        }
        if showShortcuts { showShortcuts = false; return }
        if let r = recents { clickRecents(r, at: p); return }
        if showQuickPanel { clickQuickPanel(at: p); return }
        if let b = banner, bannerRect.contains(p) { openNotification(b); return }

        if showLauncher {
            let all = launcherItems
            for i in all.indices where launcherItemRect(i).contains(p) {
                showLauncher = false
                open(all[i])
                return
            }
            if all.isEmpty, launcherSearchRect.contains(p) { searchWebFromLauncher(); return }
            if launcherShowsAppsHint, launcherAppsHintRect.contains(p) { showLauncher = false; openPage(.apps); return }
            if launcherRect.contains(p) { return }
            showLauncher = false
            if startButtonRect.contains(p) { return }
        }

        if p.y >= taskbarHitTop { clickTaskbar(p); return }

        // A sticky note: its × deletes it, anywhere else starts typing in it.
        if let i = stickyIndex(at: p) {
            focusedID = nil
            selectedIcon = nil
            let note = stickies[i]
            if stickyCloseRect(note).contains(p) {
                stickies.remove(at: i)
                if editingSticky == note.id { editingSticky = nil }
                return
            }
            stickies.append(stickies.remove(at: i))
            editingSticky = note.id
            return
        }
        if let w = topWindow(at: p) {
            selectedIcon = nil
            focus(w)
            let f = w.frame
            if !w.isFullscreen {   // fullscreen: no title bar, the top-left corner is page content
                if Layout.closeButton(in: f).insetBy(dx: -4, dy: -4).contains(p) { close(w); return }
                if Layout.minimizeButton(in: f).insetBy(dx: -4, dy: -4).contains(p) { minimize(w); return }
                if Layout.maximizeButton(in: f).insetBy(dx: -4, dy: -4).contains(p) {
                    if w.floatingRestore != nil { toggleFloatingVideo(w) } else { toggleMaximize(w) }
                    return
                }
            }
            if !w.isFullscreen, p.y < f.minY + Layout.titleBar {
                if w.showsTabs, clickTabs(w, at: p) { return }
                if isDouble { toggleMaximize(w) }   // double click on the title bar = maximize / restore
                return
            }
            if w.showsAddressBar, let web = w.webView, !w.isFullscreen, Layout.addressRow(in: f).contains(p) {
                clickAddressBar(w, web, at: p)
                return
            }
            if w.showsBookmarksBar, !w.isFullscreen, Layout.bookmarksRow(in: f).contains(p) {
                clickBookmarksBar(w, at: p)
                return
            }
            w.addressDraft = nil       // clicking the page leaves the address field
            if let guest = w.guestWindow {
                tapGuest(guest, at: localPoint(p, in: w), hold: 0.06)
            } else if let web = w.webView {
                WebInput.click(web, at: localPoint(p, in: w), count: isDouble ? 2 : 1)
            }
            return
        }

        if let k = widget(at: p) { focusedID = nil; clickWidget(k, at: p); return }
        // Desktop background: click selects an icon, double click opens it.
        focusedID = nil
        if let hit = desktopIcon(at: p) {
            if isDouble && selectedIcon == hit.slot {
                selectedIcon = nil
                open(hit.item)
            } else {
                selectedIcon = hit.slot
            }
        } else {
            selectedIcon = nil
        }
    }

    /// Sends synthetic touches to the guest app on the next run loop turn instead of immediately.
    /// A mouse button or a real touch on the iPhone arrives as a touch event; sending another touch event to the
    /// guest window while UIKit is still dispatching the real one often gets the synthetic touch ignored
    /// (left clicks in the app did nothing). The main queue is FIFO, so down → move → up stay in order.
    private static func guestInput(_ work: @escaping () -> Void) {
        DispatchQueue.main.async(execute: work)
    }

    /// Puts a finger down in the app's window that is on top at that point (an overlay window, or the main one).
    private static func touchDown(at point: CGPoint, in guest: UIWindow) {
        GuestRuntime.activateApp(with: guest)
        GuestTouch.begin(at: point, in: GuestRuntime.touchWindow(at: point, appWindow: guest))
    }

    /// Taps the guest app: finger down, then up after `hold` seconds.
    private func tapGuest(_ guest: UIWindow, at point: CGPoint, hold: TimeInterval) {
        guard !isGuestDrag else { return }
        Self.guestInput { Self.touchDown(at: point, in: guest) }
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            guard let self, !self.isGuestDrag else { return }
            GuestTouch.end()
        }
    }

    private func taskEntry(at p: CGPoint) -> TaskEntry? {
        taskLayout.first { $0.rect.contains(p) }?.entry
    }

    private func clickTaskbar(_ p: CGPoint) {
        cancelTaskPreview()
        if startButtonRect.contains(p) { showLauncher.toggle(); return }
        if showDesktopRect.contains(p) { toggleShowDesktop(); return }
        if navButtonRect(.search).contains(p) { toggleSpotlight(); return }
        if navButtonRect(.recents).contains(p) { toggleRecents(); return }
        if let r = recordButtonRect, r.contains(p) { ScreenRecorder.shared.stop(); return }
        if let r = downloadsButtonRect, r.contains(p) { let open = !showDownloads; closePanels(); showDownloads = open; return }
        if taskManagerButtonRect.contains(p) { let open = !showTaskManager; closePanels(); showTaskManager = open; return }
        if trayRect.contains(p) { showQuickPanel = true; return }
        if navButtonRect(.home).contains(p) { goHome(); return }
        if navButtonRect(.back).contains(p) { goBack(); return }
        if workspacesEnabled, let n = (0..<Self.workspaceCount).first(where: { workspaceCellRect($0).contains(p) }) { setWorkspace(n); return }
        switch taskEntry(at: p) {
        case let .pinned(item, nil)?: open(item)
        case let entry?:
            guard let w = entry.window else { return }
            if focusedID == w.id && w.isShown { minimize(w) } else { focus(w) }
        case nil: break
        }
    }

    // MARK: Middle click

    /// Middle button, as in a desktop browser: on a tab it closes the tab, on a link it opens it in a background tab;
    /// on a window's taskbar button it closes the window.
    func middleClick() {
        if isLocked || showScreenSaver { noteInput(); return }
        let p = cursor.position
        flashPress()
        guard quickLook == nil, contextMenu == nil, recents == nil, !showQuickPanel else { return }
        if p.y >= taskbarHitTop {
            if let w = taskEntry(at: p)?.window { close(w) }
            return
        }
        guard let w = topWindow(at: p), !w.isFullscreen else { return }
        if w.showsTabs, p.y < w.frame.minY + Layout.titleBar {
            let n = w.tabs.count
            if let i = (0..<n).first(where: { Layout.tabRect($0, count: n, in: w.frame).contains(p) }) { closeTab(i, of: w) }
            return
        }
        guard let web = w.webView, isOverContent(p, of: w) else { return }
        WebInput.contextInfo(web, at: localPoint(p, in: w)) { [weak self, weak w] _, href in
            guard let self, let w, let link = href.flatMap(URL.init(string:)) else { return }
            if w.isBrowser { w.newTab(link, activate: false) } else { self.openWindow(link) }
            self.scheduleSave()
        }
    }

    // MARK: Right click

    func rightClick() {
        if isLocked || showScreenSaver { noteInput(); return }
        let p = cursor.position
        flashPress()
        contextMenu = nil
        if quickLook != nil { return }
        if capture != nil { capture = nil; return }
        if showSpotlight { showSpotlight = false; return }
        if showClipboard { if let menu = clipboardMenu(at: p) { presentMenu(menu, at: p) } else { showClipboard = false }; return }
        fillSuggestion = nil
        if recents != nil { closeRecents(); return }
        if showQuickPanel { showQuickPanel = false; return }

        // App menu: an app's menu (open, pin), the menu stays open behind it.
        if showLauncher, launcherRect.contains(p) {
            let all = launcherItems
            if let i = all.indices.first(where: { launcherItemRect($0).contains(p) }) { presentMenu(itemMenu(all[i]), at: p) }
            return
        }
        showLauncher = false

        if p.y >= taskbarHitTop {
            guard let entry = taskEntry(at: p) else { presentMenu(desktopMenuItems(), at: p); return }
            var menu: [MenuItem] = []
            if let w = entry.window {
                menu = [
                    MenuItem(w.isMinimized ? "Show window" : "Minimize", w.isMinimized ? "macwindow" : "minus") { [weak self] in
                        guard let self else { return }
                        if w.isMinimized { self.focus(w) } else { self.minimize(w) }
                    },
                    MenuItem(w.isMaximized ? "Restore size" : "Maximize", "arrow.up.left.and.arrow.down.right") { [weak self] in
                        self?.focus(w); self?.toggleMaximize(w)
                    },
                    .separator,
                ]
            }
            // An app can be pinned from its window; a pinned app can be unpinned.
            let item: Shortcut? = {
                if case let .pinned(item, _) = entry { return item }
                guard let app = entry.window?.guestApp else { return nil }
                return items.first { $0.app == app }
            }()
            if let item {
                if entry.window == nil {
                    menu.append(MenuItem("Open", "arrow.up.forward.app") { [weak self] in self?.open(item) })
                }
                menu.append(MenuItem(isPinned(item) ? "Unpin from taskbar" : "Pin to taskbar",
                                     isPinned(item) ? "pin.slash" : "pin") { [weak self] in self?.togglePin(item) })
            }
            if let w = entry.window {
                menu += [.separator, MenuItem("Close window", "xmark") { [weak self] in self?.close(w) }]
            }
            presentMenu(menu, at: p)
            return
        }

        if let i = stickyIndex(at: p) {
            presentMenu(stickyMenu(stickies[i]), at: p)
            return
        }
        if let w = topWindow(at: p) {
            focus(w)
            if w.showsBookmarksBar, !w.isFullscreen, Layout.bookmarksRow(in: w.frame).contains(p) {
                presentMenu(bookmarksBarMenu(w, at: p), at: p)
                return
            }
            if p.y < w.frame.minY + w.chromeHeight {
                presentMenu(windowMenuItems(w), at: p)
                return
            }
            if let guest = w.guestWindow {
                // Right click in a guest app = long press (iOS context menu).
                tapGuest(guest, at: localPoint(p, in: w), hold: 0.7)
                return
            }
            guard let web = w.webView else { return }
            WebInput.contextInfo(web, at: localPoint(p, in: w)) { [weak self, weak w] handled, href in
                // The page has its own context menu (Google Docs, Drive…): let it handle the click.
                guard let self, let w, !handled else { return }
                self.presentMenu(self.webMenuItems(w, web, link: href.flatMap(URL.init(string:))), at: p)
            }
            return
        }

        if widget(at: p) != nil { presentMenu(widgetsMenu(), at: p); return }
        if let hit = desktopIcon(at: p) {
            selectedIcon = hit.slot
            presentMenu(itemMenu(hit.item), at: p)
            return
        }
        presentMenu(desktopMenuItems(), at: p)
    }

    private func presentMenu(_ items: [MenuItem], at p: CGPoint) {
        let h = items.reduce(Layout.menuPadding * 2) { $0 + $1.height }
        let w = Layout.menuWidth
        var x = p.x, y = p.y
        if x + w > screenSize.width { x = p.x - w }
        if y + h > screenSize.height { y = p.y - h }
        contextMenu = ContextMenu(items: items, frame: CGRect(x: max(0, x), y: max(0, y), width: w, height: h))
        cursor.setStyle(.arrow)
    }

    private func desktopMenuItems() -> [MenuItem] {
        let anyVisible = windows.contains { $0.isShown }
        return [
            MenuItem("New window", "plus.rectangle.on.rectangle") { [weak self] in self?.newBrowserWindow() },
            MenuItem("New sticky note", "note.text.badge.plus") { [weak self] in self?.newSticky(at: self?.cursor.position) },
            MenuItem("Reopen closed window or tab", "arrow.uturn.backward", enabled: canReopenClosed) { [weak self] in self?.reopenClosed() },
            .separator,
            MenuItem("Tile windows", "rectangle.split.2x2", enabled: anyVisible) { [weak self] in self?.tileWindows() },
            MenuItem("Cascade windows", "square.stack", enabled: anyVisible) { [weak self] in self?.cascadeWindows() },
            MenuItem(anyVisible ? "Show desktop" : "Show windows again", "menubar.dock.rectangle",
                     enabled: !windows.isEmpty) { [weak self] in self?.toggleShowDesktop() },
            .separator,
            MenuItem("Change wallpaper", "photo") { [weak self] in self?.nextWallpaper() },
            MenuItem(autoHideTaskbar ? "Always show the taskbar" : "Auto-hide the taskbar",
                     autoHideTaskbar ? "dock.rectangle" : "dock.arrow.down.rectangle") { [weak self] in
                self?.autoHideTaskbar.toggle()
            },
            MenuItem(showWidgets ? "Hide widgets" : "Show widgets", "clock") { [weak self] in self?.showWidgets.toggle() },
            MenuItem("Choose widgets…", "square.grid.2x2") { [weak self] in
                guard let self else { return }
                DispatchQueue.main.async { self.presentMenu(self.widgetsMenu(), at: self.cursor.position) }
            },
            MenuItem("Keyboard shortcuts", "keyboard") { [weak self] in self?.showShortcuts = true },
            MenuItem("Lock the desktop", "lock") { [weak self] in self?.lockDesktop(force: true) },
            MenuItem("Clipboard history", "list.clipboard") { [weak self] in self?.toggleClipboard() },
            MenuItem("Screenshot of an area", "camera.viewfinder") { [weak self] in self?.startAreaCapture() },
            MenuItem(ScreenRecorder.shared.isRecording ? "Stop recording" : "Record the screen", "record.circle") {
                ScreenRecorder.shared.toggle()
            },
            .separator,
            MenuItem("Apps", "square.and.arrow.down") { [weak self] in self?.openPage(.apps) },
            MenuItem("Settings", "gearshape") { [weak self] in self?.openPage(.settings) },
        ]
    }

    private func windowMenuItems(_ w: DeskWindow) -> [MenuItem] {
        var items = [
            MenuItem(w.isMaximized ? "Restore size" : "Maximize",
                     w.isMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") { [weak self] in
                self?.toggleMaximize(w)
            },
            MenuItem("Minimize", "minus") { [weak self] in self?.minimize(w) },
            MenuItem(w.keepOnTop ? "Stop keeping on top" : "Keep on top", w.keepOnTop ? "pin.slash" : "pin") { [weak self] in
                self?.toggleKeepOnTop(w)
            },
            MenuItem("Present", "play.rectangle") { [weak self] in self?.startPresentation(w) },
            MenuItem("Snap left", "rectangle.lefthalf.filled") { [weak self] in self?.snap(w, .left) },
            MenuItem("Snap right", "rectangle.righthalf.filled") { [weak self] in self?.snap(w, .right) },
            .separator,
        ]
        if w.isApp {
            // An app made for a phone can be shown at phone or tablet size, or turned sideways.
            items += [
                MenuItem("Phone size", "iphone") { [weak self] in self?.resizeApp(w, .phone) },
                MenuItem("Tablet size", "ipad") { [weak self] in self?.resizeApp(w, .tablet) },
                MenuItem("Landscape", "iphone.landscape") { [weak self] in self?.resizeApp(w, .landscape) },
            ]
            if let app = w.guestApp {
                let fills = DeskWindow.fillsWindow(app)
                items.append(MenuItem(fills ? "Keep a phone shape when maximized" : "Fill the window when maximized",
                                      fills ? "iphone" : "rectangle.inset.filled") { [weak self] in
                    w.setFillsWindow(!fills)
                    self?.objectWillChange.send()
                })
            }
            items.append(.separator)
        }
        if w.systemPage != nil, let web = w.webView {
            items += [MenuItem("Reload", "arrow.clockwise") { web.reload() }, .separator]
        }
        if w.isBrowser, w.webView != nil {
            items.append(MenuItem(w.floatingRestore == nil ? "Floating video" : "Back to the page",
                                  w.floatingRestore == nil ? "pip.enter" : "pip.exit") { [weak self] in self?.toggleFloatingVideo(w) })
        }
        if w.isBrowser, let web = w.webView {
            items += [
                MenuItem("New tab", "plus.square.on.square") { [weak self] in self?.newTab(in: w) },
                MenuItem("Reload", "arrow.clockwise") { web.reload() },
                .separator,
            ]
            if w.tabs.count > 1, let i = (0..<w.tabs.count).first(where: {
                Layout.tabRect($0, count: w.tabs.count, in: w.frame).contains(cursor.position) }) {
                items.insert(contentsOf: [
                    MenuItem("Close tab", "xmark.square") { [weak self] in self?.closeTab(i, of: w) },
                MenuItem("Move tab to a window beside", "rectangle.split.2x1") { [weak self] in
                    w.selectTab(i)
                    self?.splitTab(w)
                },
                    MenuItem("Close other tabs", "xmark.square.fill") { [weak self] in
                        guard let self else { return }
                        let keep = w.tabs[i]
                        while w.tabs.count > 1 { if !w.closeTab(w.tabs.firstIndex(where: { $0 !== keep }) ?? 0) { break } }
                        self.scheduleSave()
                    },
                    .separator,
                ], at: 0)
            }
        }
        for n in 0..<Self.workspaceCount where workspacesEnabled && n != w.workspace {
            items.append(MenuItem("Move to workspace \(n + 1)", "rectangle.stack") { [weak self] in self?.move(w, toWorkspace: n) })
        }
        items.append(.separator)
        items.append(MenuItem("Close", "xmark") { [weak self] in self?.close(w) })
        return items
    }

    private func webMenuItems(_ w: DeskWindow, _ web: WKWebView, link: URL?) -> [MenuItem] {
        // In one of iDesk's own apps: what a link offers, and Reload; nothing about pages or addresses.
        if !w.isBrowser {
            var items = [MenuItem("Reload", "arrow.clockwise") { web.reload() }]
            if let link {
                items += [
                    .separator,
                    MenuItem("Open link in new window", "macwindow.badge.plus") { [weak self] in self?.openWindow(link) },
                    MenuItem("Copy link", "link") { ClipboardHistory.shared.copy(link) },
                ]
            }
            return items
        }
        var items = [
            MenuItem("Back", "chevron.left", enabled: web.canGoBack) { web.goBack() },
            MenuItem("Forward", "chevron.right", enabled: web.canGoForward) { web.goForward() },
            MenuItem("Reload", "arrow.clockwise") { web.reload() },
            .separator,
            MenuItem("Find in page…", "magnifyingglass") { [weak self] in self?.findInPage() },
            MenuItem("Zoom in", "plus.magnifyingglass") { [weak self] in self?.zoom(1) },
            MenuItem("Zoom out", "minus.magnifyingglass") { [weak self] in self?.zoom(-1) },
            MenuItem("Actual size", "1.magnifyingglass", enabled: abs(PageZoom.zoom(of: web) - PageZoom.standard) > 0.01) { [weak self] in self?.zoom(0) },
        ]
        if let link {
            items += [
                .separator,
                MenuItem("Open link in new tab", "plus.square.on.square", enabled: w.isBrowser) { [weak self] in
                    self?.newTab(in: w, url: link)
                },
                MenuItem("Open link in new window", "macwindow.badge.plus") { [weak self] in self?.openWindow(link) },
                MenuItem("Copy link", "link") { ClipboardHistory.shared.copy(link) },
            ]
        }
        items += [
            .separator,
            MenuItem("Copy page address", "doc.on.doc") { ClipboardHistory.shared.copy(w.currentURL) },
        ]
        if let url = web.url, Browsing.isWebPage(url) {
            let marked = Browsing.shared.isBookmarked(url)
            items += [
                MenuItem(marked ? "Remove bookmark" : "Bookmark this page", marked ? "star.slash" : "star") { [weak self] in
                    self?.toggleBookmark(w)
                },
                MenuItem("Add to desktop", "plus.app", enabled: !Browsing.shared.isOnDesktop(url.absoluteString)) { [weak self] in
                    self?.addToDesktop(w)
                },
                MenuItem("Install as app", "app.badge", enabled: !w.isWebApp && !WebApps.shared.isInstalled(url.absoluteString)) { [weak self] in
                    self?.installWebApp(w)
                },
                .separator,
                MenuItem("Translate page", "character.bubble") { [weak self] in self?.translatePage(w) },
                MenuItem("Reader view", "doc.plaintext") { [weak self] in self?.toggleReader(w) },
                MenuItem(ContentBlocker.isAllowed(url) ? "Block ads on this site" : "Don't block ads on this site",
                         ContentBlocker.isAllowed(url) ? "hand.raised" : "hand.raised.slash", enabled: ContentBlocker.isEnabled) {
                    ContentBlocker.toggleAllowed(url)
                    web.reload()
                },
                MenuItem(ReadAloud.shared.isSpeaking ? "Stop reading" : "Read aloud",
                         ReadAloud.shared.isSpeaking ? "stop.circle" : "speaker.wave.2") { [weak self] in self?.readAloud(w) },
            ]
        }
        return items
    }

    // MARK: Find in page, zoom

    /// ⌘F: the find bar of the focused page (typing goes there; Enter: next, ⇧Enter: previous, Esc: close).
    func findInPage() {
        guard let w = focused, let web = w.webView else { return }
        // The text editor has its own find and replace bar (a text area's text can't be marked from outside).
        if DesktopPage(web.url) == .editor { web.evaluateJavaScript("window.ideskFind && ideskFind()"); return }
        w.addressDraft = nil
        if w.findQuery == nil { w.findQuery = "" }
    }

    func findAgain(backwards: Bool) {
        guard let w = focused else { return }
        if let web = w.webView, DesktopPage(web.url) == .editor {
            web.evaluateJavaScript("window.ideskFindNext && ideskFindNext(\(backwards ? -1 : 1))"); return
        }
        guard w.findQuery != nil else { return }
        w.runFind(step: backwards ? -1 : 1)
    }

    func closeFind(_ w: DeskWindow) {
        w.findQuery = nil
    }

    /// ⌘+ / ⌘− / ⌘0: the page's zoom, as in a desktop browser.
    func zoom(_ step: Int) {
        guard let web = focused?.webView else { return }
        let levels: [CGFloat] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]
        let current = PageZoom.zoom(of: web)
        let next: CGFloat
        if step == 0 { next = PageZoom.standard }
        else if step > 0 { next = levels.first { $0 > current + 0.01 } ?? levels.last! }
        else { next = levels.last { $0 < current - 0.01 } ?? levels.first! }
        PageZoom.set(next, for: web)
        showToast(String(localized: "Zoom \(Int((next * 100).rounded()))%"))
    }

    func scroll(dx: CGFloat, dy: CGFloat) {
        if isLocked || showScreenSaver { noteInput(); return }
        let p = cursor.position
        if quickLook != nil {
            if quickLookRect.contains(p) { QuickLook.scroll(dx: dx, dy: dy) }
            return
        }
        guard contextMenu == nil, recents == nil, !showQuickPanel, p.y < taskbarHitTop, let w = topWindow(at: p), isOverContent(p, of: w) else { return }
        if let guest = w.guestWindow {
            let local = localPoint(p, in: w)
            Self.guestInput {
                GuestTouch.scroll(at: local, in: GuestRuntime.touchWindow(at: local, appWindow: guest), dx: dx, dy: dy)
            }
        } else if let web = w.webView {
            WebInput.scroll(web, at: localPoint(p, in: w), dx: dx, dy: dy)
        }
    }

    private func localPoint(_ p: CGPoint, in w: DeskWindow) -> CGPoint {
        CGPoint(x: p.x - w.frame.minX - w.guestRect.minX, y: p.y - w.frame.minY - w.chromeHeight - w.guestRect.minY)
    }

    private func flashPress() {
        cursor.isPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, !self.isDragging else { return }
            self.cursor.isPressed = false
        }
    }

    // MARK: Address bar

    private func clickAddressBar(_ w: DeskWindow, _ web: WKWebView, at p: CGPoint) {
        let f = w.frame
        if Layout.backButton(in: f).contains(p) { w.addressDraft = nil; web.goBack() }
        else if Layout.forwardButton(in: f).contains(p) { w.addressDraft = nil; web.goForward() }
        else if Layout.reloadButton(in: f).contains(p) {
            w.addressDraft = nil
            if web.isLoading { web.stopLoading() } else { web.reload() }
        }
        else if Layout.addressField(in: f).contains(p) { w.addressDraft = "" }
        else if Layout.bookmarkButton(in: f).contains(p) { toggleBookmark(w) }
        else if Layout.browserMenuButton(in: f).contains(p) {
            w.addressDraft = nil
            let b = Layout.browserMenuButton(in: f)
            presentMenu(browserMenuItems(w), at: CGPoint(x: b.maxX - 240, y: b.maxY + 2))
        }
    }

    /// ⋯ in the address bar, as Chrome's menu.
    private func browserMenuItems(_ w: DeskWindow) -> [MenuItem] {
        let browsing = Browsing.shared
        return [
            MenuItem("New tab", "plus.square.on.square") { [weak self] in self?.newTab(in: w) },
            MenuItem("New window", "plus.rectangle.on.rectangle") { [weak self] in self?.newBrowserWindow() },
            .separator,
            MenuItem("History", "clock.arrow.circlepath") { [weak self] in self?.openPage(.history) },
            MenuItem("Bookmarks", "book") { [weak self] in self?.openPage(.history) },
            MenuItem(browsing.showsBookmarksBar ? "Hide bookmarks bar" : "Show bookmarks bar", "menubar.rectangle") {
                browsing.showsBookmarksBar.toggle()
            },
            MenuItem("Downloads", "arrow.down.circle") { [weak self] in self?.showDownloads = true },
            .separator,
            MenuItem("Find on page", "magnifyingglass") { [weak self] in self?.findInPage() },
            MenuItem("Browser settings", "gearshape") { [weak self] in self?.openPage(.browser) },
        ]
    }

    // MARK: Bookmarks bar

    private func clickBookmarksBar(_ w: DeskWindow, at p: CGPoint) {
        let marks = Browsing.shared.bookmarks
        let layout = Layout.bookmarkItems(marks.map(\.title), in: w.frame)
        w.addressDraft = nil
        if let i = layout.items.firstIndex(where: { $0.contains(p) }) {
            openBookmark(marks[i], in: w)
        } else if let more = layout.more, more.contains(p) {
            let rest = marks.dropFirst(layout.items.count).map { mark in
                MenuItem(verbatim: mark.title, "globe") { [weak self] in self?.openBookmark(mark, in: w) }
            }
            presentMenu(Array(rest), at: CGPoint(x: more.maxX - 240, y: more.maxY + 2))
        }
    }

    private func openBookmark(_ mark: WebEntry, in w: DeskWindow, newTab: Bool = false) {
        guard let url = URL(string: mark.url) else { return }
        if newTab { self.newTab(in: w, url: url); w.addressDraft = nil } else { w.load(url) }
    }

    private func bookmarksBarMenu(_ w: DeskWindow, at p: CGPoint) -> [MenuItem] {
        let browsing = Browsing.shared
        let marks = browsing.bookmarks
        let layout = Layout.bookmarkItems(marks.map(\.title), in: w.frame)
        var items: [MenuItem] = []
        if let i = layout.items.firstIndex(where: { $0.contains(p) }) {
            let mark = marks[i]
            items += [
                MenuItem("Open", "arrow.up.right.square") { [weak self] in self?.openBookmark(mark, in: w) },
                MenuItem("Open in new tab", "plus.square.on.square") { [weak self] in self?.openBookmark(mark, in: w, newTab: true) },
                MenuItem("Copy address", "doc.on.doc") { ClipboardHistory.shared.copy(mark.url) },
                MenuItem("Remove bookmark", "star.slash") { browsing.removeBookmark(mark.url) },
                .separator,
            ]
        }
        items += [
            MenuItem("Bookmarks and history", "book") { [weak self] in self?.openPage(.history) },
            MenuItem("Hide bookmarks bar", "menubar.rectangle") { browsing.showsBookmarksBar = false },
        ]
        return items
    }

    // MARK: Bookmarks & desktop shortcuts

    /// The ☆ in the address bar (and the page's right-click menu).
    func toggleBookmark(_ w: DeskWindow) {
        guard let url = w.webView?.url, Browsing.isWebPage(url) else { return }
        Browsing.shared.toggleBookmark(url, title: w.title)
        showToast(Browsing.shared.isBookmarked(url) ? String(localized: "Bookmarked.") : String(localized: "Bookmark removed."))
    }

    func addToDesktop(_ w: DeskWindow) {
        guard let url = w.webView?.url, Browsing.isWebPage(url) else { return }
        Browsing.shared.addToDesktop(url, title: w.title)
        showToast(String(localized: "Added to the desktop and the app menu."))
    }

    /// ⌘L (or a click on the field): type a new address for the focused web window.
    func focusAddressBar() {
        guard let w = focused, w.showsAddressBar, !w.isFullscreen else { return }
        w.addressDraft = ""
    }

    /// ⌘T / ⌘N: a new browser window, ready for an address.
    func newBrowserWindow() {
        openWindow("https://www.google.com")
        focusAddressBar()
    }

    // MARK: Tabs

    /// A click in a web window's tab strip: a tab, its ×, or "+". False if it hit none of them.
    private func clickTabs(_ w: DeskWindow, at p: CGPoint) -> Bool {
        let f = w.frame, n = w.tabs.count
        if Layout.newTabRect(count: n, in: f).contains(p) { newTab(in: w); return true }
        for i in 0..<n where Layout.tabRect(i, count: n, in: f).contains(p) {
            if Layout.tabCloseRect(i, count: n, in: f).insetBy(dx: -3, dy: -3).contains(p) { closeTab(i, of: w) }
            else { w.selectTab(i) }
            return true
        }
        return false
    }

    func newTab(in w: DeskWindow, url: URL = URL(string: "https://www.google.com")!) {
        w.newTab(url)
        focus(w)
        w.addressDraft = ""
        scheduleSave()
    }

    func closeTab(_ i: Int, of w: DeskWindow) {
        let url = w.url(ofTab: i)
        if w.closeTab(i) { remember(.tab(url, window: w.id)) } else { close(w) }
        scheduleSave()
    }

    /// ⌘T: a new tab in the focused browser window (a new window when an app is focused).
    func newTabOrWindow() {
        if let w = focused, w.showsAddressBar, w.isShown { newTab(in: w) } else { newBrowserWindow() }
    }

    /// Ctrl+Tab (Shift: backwards): the next tab of the focused browser window; with one tab, the window switcher.
    func nextTab(backwards: Bool) {
        guard let w = focused, w.isBrowser, w.tabs.count > 1 else { cycleWindows(); return }
        w.selectTab((w.activeTab + (backwards ? -1 : 1) + w.tabs.count) % w.tabs.count)
    }

    /// ⌘1…9: that tab (9: the last one).
    func selectTab(number n: Int) {
        guard let w = focused, w.isBrowser, !w.tabs.isEmpty else { return }
        w.selectTab(n == 9 ? w.tabs.count - 1 : min(n - 1, w.tabs.count - 1))
    }

    // MARK: Files


    /// Files, Settings or Apps in a window on the desktop.
    func openPage(_ page: DesktopPage) {
        showLauncher = false
        openWindow(page.url)
    }

    func refreshFilesPages() { windows.forEach { $0.refreshFilesPages() } }

    /// The iPhone's share sheet for a file: save it to Photos or Files, or send it to another app.
    func shareOnPhone(_ files: [URL]) {
        guard var top = PhoneWindow.current?.rootViewController else { return }
        while let p = top.presentedViewController, !p.isBeingDismissed { top = p }
        let sheet = UIActivityViewController(activityItems: files, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = top.view
        top.present(sheet, animated: true)
        showToast(String(localized: "Choose where to save it on the iPhone."))
    }

    private func commitAddress(_ w: DeskWindow) {
        let text = (w.addressDraft ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        w.addressDraft = nil
        guard !text.isEmpty else { return }
        let url = Self.url(from: text)
        if let page = DesktopPage(url) { openPage(page); return }      // iDesk's own apps open in their own window
        w.load(url)
    }

    /// The focused web window whose address field is being edited, if any.
    private var editingAddress: DeskWindow? {
        guard let w = focused, w.addressDraft != nil else { return nil }
        return w
    }

    // MARK: Keyboard & navigation (act on the focused window)

    func typeText(_ s: String) {
        if isLocked || showScreenSaver { noteInput(); return }
        noteInput()
        if quickLook != nil { if s == " " { quickLook = nil }; return }
        if recents != nil { return }
        if showSpotlight { spotlightQuery += s.replacingOccurrences(of: "\n", with: ""); return }
        if showClipboard { return }
        if let id = editingSticky, let i = stickies.firstIndex(where: { $0.id == id }) { stickies[i].text += s; return }
        if showLauncher { launcherQuery += s; return }
        if let w = focused, w.findQuery != nil {
            w.findQuery? += s.replacingOccurrences(of: "\n", with: "")
            w.runFind()
            return
        }
        if let w = editingAddress { w.addressDraft? += s.replacingOccurrences(of: "\n", with: ""); return }
        // Space in Files previews the selected file (Quick Look), unless a text field there (search, rename) has focus.
        if s == " ", let w = focused, w.systemPage == .files, !w.filesEditing { toggleQuickLook(); return }
        if showEmoji { return }
        // A text replacement code just ended: the code goes, the phrase takes its place.
        if let r = TextReplacements.check(s) {
            for _ in 0..<r.delete { backspace() }
            send(r.phrase + s)
            return
        }
        send(s)
    }

    /// Types into the app or page in front.
    private func send(_ s: String) {
        if let guest = focused?.guestWindow { Self.inAppWindows(of: guest) { GuestTouch.insertText(s, in: $0) } }
        else if let web = focused?.webView { WebInput.type(web, text: s) }
    }
    func backspace() {
        if isLocked || showScreenSaver { noteInput(); return }
        if let r = recents {
            if r.ids.indices.contains(r.index), let w = window(r.ids[r.index]) { closeFromRecents(w) }
            return
        }
        if showLauncher { if !launcherQuery.isEmpty { launcherQuery.removeLast() }; return }
        if showSpotlight { if !spotlightQuery.isEmpty { spotlightQuery.removeLast() }; return }
        if showClipboard {
            let all = ClipboardHistory.shared.ordered
            if all.indices.contains(clipboardIndex) { ClipboardHistory.shared.remove(all[clipboardIndex].id) }
            clipboardIndex = max(0, min(clipboardIndex, ClipboardHistory.shared.items.count - 1))
            return
        }
        if let id = editingSticky, let i = stickies.firstIndex(where: { $0.id == id }) {
            if !stickies[i].text.isEmpty { stickies[i].text.removeLast() }
            return
        }
        if let w = focused, w.findQuery != nil {
            if w.findQuery?.isEmpty == false { w.findQuery?.removeLast(); w.runFind() }
            return
        }
        if let w = editingAddress { if w.addressDraft?.isEmpty == false { w.addressDraft?.removeLast() }; return }
        if let guest = focused?.guestWindow { Self.inAppWindows(of: guest) { GuestTouch.deleteBackward(in: $0) } }
        else if let web = focused?.webView { WebInput.backspace(web) }
    }
    func pressEnter() {
        if isLocked || showScreenSaver { noteInput(); return }
        if recents != nil { commitRecents(); return }
        if showSpotlight { commitSpotlight(); return }
        if showClipboard { pasteFromClipboard(); return }
        if showEmoji { insertEmoji(); return }
        if let id = editingSticky, let i = stickies.firstIndex(where: { $0.id == id }) { stickies[i].text += "\n"; return }
        if showLauncher {
            if let first = launcherItems.first { showLauncher = false; open(first) } else { searchWebFromLauncher() }
            return
        }
        if let w = focused, w.findQuery != nil { w.runFind(step: 1); return }      // Enter: the next match
        if let w = editingAddress { commitAddress(w); return }
        if let guest = focused?.guestWindow { Self.inAppWindows(of: guest) { GuestTouch.insertText("\n", in: $0) } }
        else if let web = focused?.webView { WebInput.enter(web) }
    }

    /// Typing goes to the text field that has focus, in whichever of the app's windows it is (top first).
    private static func inAppWindows(of guest: UIWindow, _ type: (UIWindow) -> Bool) {
        for window in GuestRuntime.windowsOfApp(with: guest).reversed() where type(window) { return }
    }

    /// Back (taskbar button, Esc in an app, Alt+←): closes what is open on top first, then goes back
    /// in the focused window — the previous page of a web window, the previous screen of an app.
    func goBack() {
        if quickLook != nil { quickLook = nil; return }
        if let w = focused, w.findQuery != nil { closeFind(w); return }
        if recents != nil { closeRecents(); return }
        if showQuickPanel { showQuickPanel = false; return }
        if contextMenu != nil { contextMenu = nil; return }
        if showLauncher { showLauncher = false; return }
        guard let w = focused, w.isShown else { return }
        if w.addressDraft != nil { w.addressDraft = nil; return }
        if w.isFullscreen { w.exitFullscreen(); return }
        if let web = w.webView { web.goBack(); return }
        if let guest = w.guestWindow { Self.guestInput { GuestRuntime.goBackInApp(with: guest) } }
    }

    /// Home: every window out of the way, the desktop shows (pressed again, they come back).
    func goHome() {
        closeRecents()
        closePanels()
        toggleShowDesktop()
    }
    func goForward() { focused?.webView?.goForward() }
    func reload() { focused?.webView?.reload() }
    /// ⌘W: the tab shown, or the window when it has one tab (or is an app).
    func closeFocused() {
        guard let w = focused else { return }
        if w.isBrowser, w.tabs.count > 1 { closeTab(w.activeTab, of: w) } else { close(w) }
    }
    func toggleLauncher() {
        guard isExternalConnected else { return }
        let open = !showLauncher
        closePanels()
        showLauncher = open
    }

    /// Closes the panels that float over the desktop (a menu, the app menu, Spotlight, the clipboard, the quick
    /// panel, the shortcuts), before something else takes their place.
    func closePanels() {
        contextMenu = nil
        showLauncher = false
        showSpotlight = false
        showClipboard = false
        showQuickPanel = false
        showShortcuts = false
        showDownloads = false
        showEmoji = false
        showTaskManager = false
    }
    func minimizeFocused() { if let w = focused { minimize(w) } }
    func sendKey(_ key: String, _ code: Int, _ shift: Bool) {
        if isLocked || showScreenSaver { noteInput(); return }
        if quickLook != nil {
            switch key {
            case "ArrowLeft", "ArrowUp": stepQuickLook(-1)
            case "ArrowRight", "ArrowDown": stepQuickLook(1)
            case "Escape": quickLook = nil
            default: break
            }
            return
        }
        if recents != nil { moveRecentsSelection(key); return }
        if showEmoji { moveEmojiSelection(key); return }
        if showSpotlight || showClipboard {
            let delta = key == "ArrowUp" ? -1 : key == "ArrowDown" ? 1 : 0
            if showSpotlight { moveSpotlightSelection(delta) } else { moveClipboardSelection(delta) }
            return
        }
        if editingSticky != nil { return }
        if let web = focused?.webView { WebInput.key(web, key: key, keyCode: code, shift: shift) }
    }
    func selectAll() {
        if let guest = focused?.guestWindow { guestEdit(#selector(UIResponderStandardEditActions.selectAll(_:)), guest) }
        else if let web = focused?.webView { WebInput.selectAll(web) }
    }
    /// ⌘C / ⌘X / ⌘V: in an app, its own copy / cut / paste (so images and rich text work too); in a page, the
    /// selected text.
    func copySelection() {
        if let id = editingSticky, let note = stickies.first(where: { $0.id == id }) {
            if !note.text.isEmpty { ClipboardHistory.shared.copy(note.text) }
            return
        }
        if let guest = focused?.guestWindow {
            let before = UIPasteboard.general.changeCount
            guestEdit(#selector(UIResponderStandardEditActions.copy(_:)), guest)
            ClipboardHistory.shared.noteAppCopy(since: before)
            return
        }
        guard let web = focused?.webView else { return }
        WebInput.selectedText(web) { s in if let s, !s.isEmpty { ClipboardHistory.shared.copy(s) } }
    }
    func cutSelection() {
        if let guest = focused?.guestWindow {
            let before = UIPasteboard.general.changeCount
            guestEdit(#selector(UIResponderStandardEditActions.cut(_:)), guest)
            ClipboardHistory.shared.noteAppCopy(since: before)
            return
        }
        guard let web = focused?.webView else { return }
        WebInput.selectedText(web) { s in
            guard let s, !s.isEmpty else { return }
            ClipboardHistory.shared.copy(s)
            WebInput.backspace(web)
        }
    }
    func paste() {
        if editingAddress == nil, !showLauncher, let guest = focused?.guestWindow {
            Self.guestInput {
                if !GuestRuntime.windowsOfApp(with: guest).reversed().contains(where: {
                    GuestTouch.performEditAction(#selector(UIResponderStandardEditActions.paste(_:)), in: $0)
                }), let s = UIPasteboard.general.string { Self.inAppWindows(of: guest) { GuestTouch.insertText(s, in: $0) } }
            }
            return
        }
        if let s = UIPasteboard.general.string, !s.isEmpty { typeText(s) }
    }

    private func guestEdit(_ action: Selector, _ guest: UIWindow) {
        Self.guestInput { Self.inAppWindows(of: guest) { GuestTouch.performEditAction(action, in: $0) } }
    }

    // MARK: Screenshot

    /// PrtSc / ⌘ + Shift + 3: a picture of the whole external display, saved to Photos and to Files.
    func takeScreenshot() { captureScreen(nil) }

    /// ⌘ + Shift + 4 / S: the pointer becomes a crosshair; drag out an area, or click a window.
    func startAreaCapture() {
        guard isExternalConnected else { return }
        closePanels()
        capture = CaptureState()
        cursor.setStyle(.crosshair)
    }

    private func finishCapture(_ rect: CGRect) {
        capture = nil
        cursor.setStyle(.arrow)
        captureScreen(rect.intersection(CGRect(origin: .zero, size: screenSize)))
    }

    /// Saves a picture of the display (or of `rect` on it) to Photos and to Files, then shows it in the corner.
    private func captureScreen(_ rect: CGRect?) {
        closePanels()
        guard isExternalConnected, let view = ExternalSceneDelegate.desktopView else { return }
        cursor.isHidden = true
        screenshotPreview = nil
        // Give the desktop a moment to redraw without the panel, the overlay and the pointer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            let format = UIGraphicsImageRendererFormat()
            format.scale = view.window?.screen.scale ?? 1
            let area = rect ?? view.bounds
            guard area.width >= 1, area.height >= 1 else { self.cursor.isHidden = false; return }
            let image = UIGraphicsImageRenderer(bounds: area, format: format).image { _ in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            }
            self.cursor.isHidden = false
            let name = String(localized: "Screenshot") + " " + Self.fileDate.string(from: Date()) + ".png"
            let url = FileStore.uniqueURL(in: FileStore.downloads, name: name)
            try? image.pngData()?.write(to: url)
            ClipboardHistory.shared.copy(image)
            self.showToast(String(localized: "Screenshot saved to Files and copied"))
            // Photos: says so when iOS refused (no permission), instead of claiming it was saved.
            Self.saveToPhotos(image) { [weak self] saved in
                self?.showToast(saved ? String(localized: "Screenshot saved to Photos, Files, and copied")
                    : String(localized: "Screenshot saved to Files and copied, not to Photos: allow APLite to add photos in the iPhone's Settings → Privacy & Security → Photos."))
            }
            if let path = FileStore.relativePath(of: url) {
                withAnimation(.easeOut(duration: 0.25)) { self.screenshotPreview = ScreenshotPreview(image: image, path: path) }
                self.screenshotPreviewWork?.cancel()
                let work = DispatchWorkItem { [weak self] in withAnimation(.easeIn(duration: 0.25)) { self?.screenshotPreview = nil } }
                self.screenshotPreviewWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
            }
        }
    }

    static func saveToPhotos(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { DispatchQueue.main.async { completion(false) }; return }
            PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAsset(from: image) }) { ok, _ in
                DispatchQueue.main.async { completion(ok) }
            }
        }
    }

    var screenshotPreviewRect: CGRect {
        guard let shot = screenshotPreview else { return .zero }
        let w: CGFloat = 220, h = min(220, w * shot.image.size.height / max(1, shot.image.size.width))
        return CGRect(x: screenSize.width - w - 20, y: taskbarTop - h - 20, width: w, height: h)
    }

    private static let fileDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f
    }()

    // MARK: Notifications & quick panel

    private func receiveGuestNotification(_ info: [String: String]) {
        let path = URL(fileURLWithPath: info["bundlePath"] ?? "").resolvingSymlinksInPath().path
        let app = apps.first { $0.bundleURL.resolvingSymlinksInPath().path == path }
        let title = info["title"].flatMap { $0.isEmpty ? nil : $0 } ?? app?.name ?? "APLite"
        let body = [info["subtitle"], info["body"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        let n = DeskNotification(app: app, title: title, body: body)
        notifications.insert(n, at: 0)
        if notifications.count > 30 { notifications.removeLast(notifications.count - 30) }
        // No banner for the app the user is looking at, or with Do not disturb.
        guard isExternalConnected, !doNotDisturb, !(app != nil && focused?.guestApp == app) else { return }
        banner = n
        bannerWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.banner = nil }
        bannerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func openNotification(_ n: DeskNotification) {
        notifications.removeAll { $0.id == n.id }
        banner = nil
        showQuickPanel = false
        if let app = n.app { openApp(app) }
    }

    var bannerRect: CGRect { CGRect(x: screenSize.width - 340, y: 12, width: 328, height: 72) }

    static let quickTileCount = 4
    private static let quickPad: CGFloat = 14, quickHeader: CGFloat = 52, quickTile: CGFloat = 64,
                       quickSlider: CGFloat = 36, quickGap: CGFloat = 12, quickListHeader: CGFloat = 30,
                       quickRow: CGFloat = 62

    var quickPanelRect: CGRect {
        let rows = notifications.isEmpty ? 0.7 : CGFloat(min(notifications.count, 5))
        let h = Self.quickPad * 2 + Self.quickHeader + Self.quickTile + Self.quickGap + Self.quickSlider + Self.quickGap
            + Self.quickListHeader + rows * Self.quickRow
        return CGRect(x: screenSize.width - 352, y: taskbarTop - h - 8, width: 344, height: h)
    }

    func quickTileRect(_ i: Int) -> CGRect {
        let r = quickPanelRect, gap: CGFloat = 6
        let w = (r.width - Self.quickPad * 2 - gap * CGFloat(Self.quickTileCount - 1)) / CGFloat(Self.quickTileCount)
        return CGRect(x: r.minX + Self.quickPad + CGFloat(i) * (w + gap), y: r.minY + Self.quickPad + Self.quickHeader,
                      width: w, height: Self.quickTile)
    }

    var quickSliderY: CGFloat { quickPanelRect.minY + Self.quickPad + Self.quickHeader + Self.quickTile + Self.quickGap }
    var brightnessDownRect: CGRect { CGRect(x: quickPanelRect.minX + Self.quickPad, y: quickSliderY, width: 36, height: 36) }
    var brightnessUpRect: CGRect { CGRect(x: quickPanelRect.maxX - Self.quickPad - 36, y: quickSliderY, width: 36, height: 36) }
    var notificationsTop: CGFloat { quickSliderY + Self.quickSlider + Self.quickGap }
    var clearNotificationsRect: CGRect {
        CGRect(x: quickPanelRect.maxX - Self.quickPad - 90, y: notificationsTop, width: 90, height: 26)
    }

    func notificationRect(_ i: Int) -> CGRect {
        CGRect(x: quickPanelRect.minX + Self.quickPad, y: notificationsTop + Self.quickListHeader + CGFloat(i) * Self.quickRow,
               width: quickPanelRect.width - Self.quickPad * 2, height: Self.quickRow - 6)
    }

    func notificationCloseRect(_ i: Int) -> CGRect {
        let r = notificationRect(i)
        return CGRect(x: r.maxX - 26, y: r.minY + 6, width: 20, height: 20)
    }

    private func clickQuickPanel(at p: CGPoint) {
        guard quickPanelRect.contains(p) else { showQuickPanel = false; return }
        switch (0..<Self.quickTileCount).first(where: { quickTileRect($0).contains(p) }) {
        case 0?: doNotDisturb.toggle()
        case 1?: autoHideTaskbar.toggle()
        case 2?: takeScreenshot()
        case 3?: showQuickPanel = false; openPage(.settings)
        default:
            if brightnessDownRect.contains(p) { externalBrightness = max(0.2, externalBrightness - 0.1) }
            else if brightnessUpRect.contains(p) { externalBrightness = min(1, externalBrightness + 0.1) }
            else if clearNotificationsRect.contains(p) { notifications = [] }
            else if let i = notifications.prefix(5).indices.first(where: { notificationRect($0).contains(p) }) {
                if notificationCloseRect(i).insetBy(dx: -4, dy: -4).contains(p) { notifications.remove(at: i) }
                else { openNotification(notifications[i]) }
            }
        }
    }

    /// Alt+Tab: shows the switcher with the previous window selected; each press selects the next one.
    /// Releasing the key (or a short pause) switches to it.
    func cycleWindows() {
        if var s = switcher {
            s.index = (s.index + 1) % s.ids.count
            switcher = s
        } else {
            let ids = deskWindows.reversed().map(\.id)     // most recent first
            guard ids.count > 1 else { return }
            switcher = Switcher(ids: ids, index: 1)
            contextMenu = nil
            showLauncher = false
        }
        switcherCommit?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commitSwitcher() }
        switcherCommit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func commitSwitcher() {
        switcherCommit?.cancel()
        guard let s = switcher else { return }
        switcher = nil
        if let w = window(s.ids[s.index]) { focus(w) }
    }

    // MARK: Recent apps

    func toggleRecents() { if recents == nil { showRecents() } else { closeRecents() } }

    /// ⌘ + Tab / the Recent apps button. Pressed again while open: selects the next window.
    func showRecents() {
        guard isExternalConnected else { return }
        if var r = recents {
            r.index = (r.index + 1) % r.ids.count
            recents = r
            return
        }
        let ids = windows.reversed().map(\.id)
        contextMenu = nil
        showLauncher = false
        switcher = nil
        recents = Switcher(ids: ids, index: ids.count > 1 ? 1 : 0)
        captureThumbnails()
        updateHover(cursor.position)
    }

    func closeRecents() {
        guard recents != nil else { return }
        recents = nil
        thumbnails = [:]          // pictures of every window are big: do not keep them around
    }

    private func commitRecents() {
        guard let r = recents, r.ids.indices.contains(r.index) else { closeRecents(); return }
        let id = r.ids[r.index]
        closeRecents()
        if let w = window(id) { focus(w) }
    }

    private func closeFromRecents(_ w: DeskWindow) {
        close(w)
        guard var r = recents else { return }
        r.ids.removeAll { $0 == w.id }
        thumbnails[w.id] = nil
        if r.ids.isEmpty { closeRecents(); return }
        r.index = min(r.index, r.ids.count - 1)
        recents = r
    }

    private func moveRecentsSelection(_ key: String) {
        guard var r = recents, !r.ids.isEmpty else { return }
        let cols = recentsColumns(r.ids.count)
        switch key {
        case "ArrowLeft": r.index = max(0, r.index - 1)
        case "ArrowRight", "Tab": r.index = min(r.ids.count - 1, r.index + 1)
        case "ArrowUp": r.index = max(0, r.index - cols)
        case "ArrowDown": r.index = min(r.ids.count - 1, r.index + cols)
        default: return
        }
        recents = r
    }

    private func clickRecents(_ r: Switcher, at p: CGPoint) {
        if recentsCloseAllRect.contains(p) {
            for w in r.ids.compactMap(window) { close(w) }
            closeRecents()
            return
        }
        for i in r.ids.indices {
            guard let w = window(r.ids[i]) else { continue }
            if recentsCloseRect(i, of: r.ids.count).insetBy(dx: -4, dy: -4).contains(p) { closeFromRecents(w); return }
            if recentsTileRect(i, of: r.ids.count).contains(p) { closeRecents(); focus(w); return }
        }
        closeRecents()       // a click on the background, or on the taskbar button again
    }

    func recentsColumns(_ count: Int) -> Int {
        let fit = Int((screenSize.width - 2 * Layout.recentsGap) / (Layout.recentsTile.width + Layout.recentsGap))
        return max(1, min(count, fit, 4))
    }

    /// Tiles centred on the desktop, in rows; they get smaller when there are too many rows to fit.
    func recentsTileRect(_ i: Int, of count: Int) -> CGRect {
        let cols = recentsColumns(count)
        let rows = (count + cols - 1) / cols
        let g = Layout.recentsGap, t = Layout.recentsTile
        let area = desktopArea.insetBy(dx: g, dy: g + 30)
        let scale = min(1, (area.height - g * CGFloat(rows - 1)) / (CGFloat(rows) * t.height))
        let w = t.width * scale, h = t.height * scale
        let totalH = CGFloat(rows) * h + CGFloat(rows - 1) * g
        let row = i / cols, col = i % cols
        // The last row is centred on its own.
        let inRow = row == rows - 1 ? count - row * cols : cols
        let rowW = CGFloat(inRow) * w + CGFloat(inRow - 1) * g
        return CGRect(x: area.midX - rowW / 2 + CGFloat(col) * (w + g),
                      y: area.midY - totalH / 2 + CGFloat(row) * (h + g), width: w, height: h)
    }

    func recentsCloseRect(_ i: Int, of count: Int) -> CGRect {
        let t = recentsTileRect(i, of: count)
        return CGRect(x: t.maxX - 28, y: t.minY + 5, width: 24, height: 24)
    }

    var recentsCloseAllRect: CGRect {
        CGRect(x: desktopArea.midX - 60, y: desktopArea.maxY - 52, width: 120, height: 36)
    }

    /// A picture of every window for Recent apps: web pages from WebKit, apps from their main window.
    private func captureThumbnails() {
        for w in windows {
            let id = w.id
            thumbnail(of: w) { [weak self] image in
                guard let self, self.recents != nil, let image else { return }
                self.thumbnails[id] = image
            }
        }
    }

    /// A small picture of a window's content: web pages from WebKit, apps from their main window.
    func thumbnail(of w: DeskWindow, completion: @escaping (UIImage?) -> Void) {
        if let web = w.webView {
            let config = WKSnapshotConfiguration()
            config.snapshotWidth = NSNumber(value: Double(Layout.recentsTile.width * 2))
            web.takeSnapshot(with: config) { image, _ in completion(image) }
        } else if let guest = w.guestWindow, let main = GuestRuntime.windowsOfApp(with: guest).first,
                  main.bounds.width > 0, main.bounds.height > 0 {
            let format = UIGraphicsImageRendererFormat()
            format.scale = min(2, Layout.recentsTile.width * 2 / main.bounds.width)
            completion(UIGraphicsImageRenderer(bounds: main.bounds, format: format).image { _ in
                main.drawHierarchy(in: main.bounds, afterScreenUpdates: false)
            })
        } else {
            completion(nil)
        }
    }

    enum AppSize { case phone, tablet, landscape }

    /// Sizes for an app window, fitted to the desktop and kept around the window's current centre.
    func resizeApp(_ w: DeskWindow, _ size: AppSize) {
        let a = desktopArea.insetBy(dx: 8, dy: 8)
        var content: CGSize
        switch size {
        case .phone: content = CGSize(width: 430, height: 800)
        case .tablet: content = CGSize(width: 820, height: 1100)
        case .landscape: content = CGSize(width: 800, height: 430)
        }
        let scale = min(1, a.width / content.width, (a.height - Layout.titleBar) / content.height)
        let s = CGSize(width: content.width * scale, height: content.height * scale + Layout.titleBar)
        let center = CGPoint(x: w.frame.midX, y: w.frame.midY)
        w.frame = CGRect(x: min(max(a.minX, center.x - s.width / 2), a.maxX - s.width),
                         y: min(max(a.minY, center.y - s.height / 2), a.maxY - s.height), width: s.width, height: s.height)
        w.isMaximized = false
        w.isSnapped = false
        focus(w)
    }

    /// Esc: close the open menu, otherwise send Esc to the page.
    /// Esc: close the open menu; in an app, Back; otherwise send Esc to the page.
    func escape() {
        if quickLook != nil { quickLook = nil; return }
        if presentation != nil { endPresentation(); return }
        if capture != nil { capture = nil; return }
        if showSpotlight { showSpotlight = false; return }
        if showClipboard { showClipboard = false; return }
        if showDownloads { showDownloads = false; return }
        if showEmoji { showEmoji = false; return }
        if fillSuggestion != nil { fillSuggestion = nil; return }
        if editingSticky != nil { editingSticky = nil; return }
        if let w = focused, w.findQuery != nil { closeFind(w); return }
        if switcher != nil { switcherCommit?.cancel(); switcher = nil; return }
        if recents != nil { closeRecents(); return }
        if showShortcuts { showShortcuts = false; return }
        if showQuickPanel { showQuickPanel = false; return }
        if contextMenu != nil { contextMenu = nil; return }
        if showLauncher { showLauncher = false; return }
        if let w = editingAddress { w.addressDraft = nil; return }
        if let w = focused, w.isFullscreen { w.exitFullscreen(); return }
        if focused?.isApp == true { goBack(); return }
        sendKey("Escape", 27, false)
    }

    static func url(from text: String) -> URL {
        if let u = URL(string: text), let s = u.scheme?.lowercased(), s == "http" || s == "https" || s == "idesk" { return u }
        if !text.contains(" "), text.contains("."), let u = URL(string: "https://" + text) { return u }
        var c = URLComponents(string: "https://www.google.com/search")!
        c.queryItems = [URLQueryItem(name: "q", value: text)]
        return c.url!
    }

    // MARK: Save / restore the session

    private struct SavedWindow: Codable {
        var url: String
        var x, y, w, h: Double
        var maximized: Bool
        var minimized: Bool
        var workspace: Int?
        var tabs: [String]?
        var activeTab: Int?
        var webApp: Bool?
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func saveNow() {
        saveWork?.cancel()
        windows.filter(\.isApp).forEach(rememberFrame)
        // Guest app windows are not saved: a crashing app would take iDesk down on every launch.
        let saved = windows.filter { !$0.isApp }.map { w -> SavedWindow in
            let current = w.fullscreenRestore?.frame ?? w.frame
            let f = (w.isMaximized || w.isSnapped) ? (w.restoreFrame ?? current) : current
            return SavedWindow(url: w.currentURL.absoluteString, x: f.minX, y: f.minY, w: f.width, h: f.height,
                               maximized: w.isMaximized, minimized: w.isMinimized, workspace: w.workspace,
                               tabs: w.tabs.indices.map { w.url(ofTab: $0).absoluteString }, activeTab: w.activeTab, webApp: w.isWebApp)
        }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Keys.session)
        }
        // The iOS apps by bundle ID, bottom to top (their frames are kept by rememberFrame).
        var appIDs: [String] = []
        for w in windows { if let id = w.guestApp?.id, !appIDs.contains(id) { appIDs.append(id) } }
        UserDefaults.standard.set(appIDs, forKey: Keys.openApps)
    }

    private func restoreSession() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Keys.session),
              let saved = try? JSONDecoder().decode([SavedWindow].self, from: data), !saved.isEmpty else { return false }
        let area = desktopArea
        for s in maxWindows > 0 ? Array(saved.suffix(maxWindows)) : saved {
            let tabs = (s.tabs ?? [s.url]).compactMap(URL.init(string:))
            guard let url = tabs.first ?? URL(string: s.url) else { continue }
            let w = min(CGFloat(s.w), area.width), h = min(CGFloat(s.h), area.height)
            let frame = CGRect(x: min(max(0, CGFloat(s.x)), area.maxX - w),
                               y: min(max(0, CGFloat(s.y)), area.maxY - h), width: w, height: h)
            let win = DeskWindow(url: url, frame: frame, system: tabs.count == 1)
            win.isWebApp = s.webApp ?? false
            for tab in tabs.dropFirst() { win.newTab(tab, activate: false) }
            win.selectTab(min(max(0, s.activeTab ?? 0), win.tabs.count - 1))
            if s.maximized {
                win.restoreFrame = frame
                win.frame = maximizedFrame
                win.isMaximized = true
            }
            win.isMinimized = s.minimized
            add(win)
            win.workspace = workspacesEnabled ? min(max(0, s.workspace ?? 0), Self.workspaceCount - 1) : 0
            win.isOffDesk = win.workspace != workspace
        }
        focusedID = windows.last(where: { $0.isShown })?.id
        return !windows.isEmpty
    }
}

// MARK: - Window layouts, sticky notes, hot corners

extension DesktopModel {
    // Window layouts picker (top edge while dragging a window)

    var tilePickerRect: CGRect {
        let n = CGFloat(TileLayouts.all.count), c = TileLayouts.cell, pad = TileLayouts.padding
        let w = pad * 2 + n * c.width + (n - 1) * TileLayouts.gap
        let h = pad * 2 + TileLayouts.title + c.height - 6
        return CGRect(x: (screenSize.width - w) / 2, y: 10, width: w, height: h)
    }

    func tileCellRect(_ layout: Int) -> CGRect {
        let r = tilePickerRect, c = TileLayouts.cell
        return CGRect(x: r.minX + TileLayouts.padding + CGFloat(layout) * (c.width + TileLayouts.gap),
                      y: r.minY + TileLayouts.padding + TileLayouts.title - 6, width: c.width, height: c.height)
    }

    /// A zone of a layout, drawn in its cell where the window would go on the screen.
    func tileZoneRect(_ layout: Int, _ zone: Int) -> CGRect {
        let cell = tileCellRect(layout).insetBy(dx: 4, dy: 4), a = maximizedFrame
        let z = snapRect(TileLayouts.all[layout][zone])
        let kx = cell.width / max(1, a.width), ky = cell.height / max(1, a.height)
        return CGRect(x: cell.minX + (z.minX - a.minX) * kx, y: cell.minY + (z.minY - a.minY) * ky,
                      width: z.width * kx, height: z.height * ky).insetBy(dx: 1.5, dy: 1.5)
    }

    func tileZone(at p: CGPoint) -> TileZone? {
        for l in TileLayouts.all.indices where tileCellRect(l).insetBy(dx: -4, dy: -4).contains(p) {
            for z in TileLayouts.all[l].indices where tileZoneRect(l, z).insetBy(dx: -2, dy: -2).contains(p) {
                return TileZone(layout: l, zone: z)
            }
        }
        return nil
    }

    // Filling the rest of the screen after a window is put in half or a third of it

    func suggestFill(after w: DeskWindow, _ s: Snap) {
        guard let zone = TileLayouts.complement(of: s) else { fillSuggestion = nil; return }
        let others = windows.reversed().filter { $0.id != w.id && $0.isShown && !$0.isFullscreen }
        // The other side already has a window that was put there: nothing to offer.
        if others.contains(where: { $0.isSnapped && $0.snap == zone }) { fillSuggestion = nil; return }
        let ids = Array(others.prefix(6).map(\.id))
        guard !ids.isEmpty else { fillSuggestion = nil; return }
        fillThumbnails = [:]
        fillSuggestion = FillSuggestion(zone: zone, ids: ids)
        for o in others.prefix(6) {
            let id = o.id
            thumbnail(of: o) { [weak self] image in if let image { self?.fillThumbnails[id] = image } }
        }
    }

    func fillArea(_ f: FillSuggestion) -> CGRect { snapRect(f.zone) }

    func fillCardRect(_ i: Int, of f: FillSuggestion) -> CGRect {
        let a = fillArea(f).insetBy(dx: 20, dy: 0)
        let gap: CGFloat = 16
        let cols = max(1, min(f.ids.count, Int((a.width + gap) / (220 + gap))))
        let rows = (f.ids.count + cols - 1) / cols
        let cw = min(260, (a.width - gap * CGFloat(cols - 1)) / CGFloat(cols))
        let ch = min(cw * 0.8, (a.height - 70 - gap * CGFloat(rows - 1)) / CGFloat(rows))
        let total = CGFloat(cols) * cw + CGFloat(cols - 1) * gap
        let x0 = a.minX + (a.width - total) / 2, y0 = a.minY + 60
        return CGRect(x: x0 + CGFloat(i % cols) * (cw + gap), y: y0 + CGFloat(i / cols) * (ch + gap), width: cw, height: ch)
    }

    // Sticky notes

    /// The top note at `p`. Notes lie on the desktop, under the windows; the one being typed in floats above them.
    func stickyIndex(at p: CGPoint) -> Int? {
        guard p.y < taskbarHitTop else { return nil }
        if let id = editingSticky, let i = stickies.firstIndex(where: { $0.id == id }), stickies[i].frame.contains(p) { return i }
        guard topWindow(at: p) == nil else { return nil }
        return stickies.indices.last { stickies[$0].frame.contains(p) }
    }

    /// The note being typed in, drawn above the windows (StickiesView draws the others under them).
    var floatingSticky: UUID? { editingSticky }

    func stickyCloseRect(_ note: StickyNote) -> CGRect {
        CGRect(x: note.frame.maxX - 28, y: note.frame.minY, width: 28, height: StickyNote.header)
    }

    func newSticky(at point: CGPoint? = nil) {
        let p = point ?? CGPoint(x: screenSize.width / 2 - 120, y: screenSize.height / 3)
        let x = min(max(8, p.x), screenSize.width - 250), y = min(max(8, p.y), taskbarTop - 220)
        let note = StickyNote(x: Double(x), y: Double(y), color: stickies.count % StickyNote.colors.count)
        stickies.append(note)
        editingSticky = note.id
        focusedID = nil
    }

    func stickyMenu(_ note: StickyNote) -> [MenuItem] {
        var items: [MenuItem] = StickyNote.colorNames.indices.map { c in
            MenuItem(StickyNote.colorNames[c], note.color == c ? "checkmark.circle.fill" : "circle") { [weak self] in
                guard let self, let i = self.stickies.firstIndex(where: { $0.id == note.id }) else { return }
                self.stickies[i].color = c
            }
        }
        items += [
            .separator,
            MenuItem("Copy text", "doc.on.doc", enabled: !note.text.isEmpty) { ClipboardHistory.shared.copy(note.text) },
            MenuItem("Larger", "plus.magnifyingglass") { [weak self] in self?.resizeSticky(note.id, by: 1.25) },
            MenuItem("Smaller", "minus.magnifyingglass") { [weak self] in self?.resizeSticky(note.id, by: 0.8) },
            MenuItem("New sticky note", "note.text.badge.plus") { [weak self] in
                self?.newSticky(at: CGPoint(x: note.frame.maxX + 16, y: note.frame.minY))
            },
            .separator,
            MenuItem("Delete note", "trash") { [weak self] in
                self?.stickies.removeAll { $0.id == note.id }
                if self?.editingSticky == note.id { self?.editingSticky = nil }
            },
        ]
        return items
    }

    private func resizeSticky(_ id: UUID, by k: Double) {
        guard let i = stickies.firstIndex(where: { $0.id == id }) else { return }
        stickies[i].width = min(520, max(160, stickies[i].width * k))
        stickies[i].height = min(480, max(140, stickies[i].height * k))
    }

    // Hot corners

    /// With hot corners on, holding the pointer in a corner a moment: top left Recent apps, top right the
    /// notifications, bottom right the desktop. It works again once the pointer has left the corner.
    private func checkHotCorner(_ p: CGPoint) {
        guard hotCorners, isExternalConnected else { return }
        let m: CGFloat = 3
        let corner: Int? = p.x <= m && p.y <= m ? 0 : p.x >= screenSize.width - 1 - m && p.y <= m ? 1
            : p.x >= screenSize.width - 1 - m && p.y >= screenSize.height - 1 - m ? 2 : nil
        guard let corner else {
            hotCornerWork?.cancel()
            if !hotCornerArmed, min(p.x, screenSize.width - p.x) > 60 || min(p.y, screenSize.height - p.y) > 60 { hotCornerArmed = true }
            return
        }
        guard hotCornerArmed else { return }
        hotCornerWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, case .none = self.drag else { return }
            self.hotCornerArmed = false
            switch corner {
            case 0: if self.recents == nil { self.toggleRecents() }
            case 1: self.showQuickPanel = true
            default: self.toggleShowDesktop()
            }
        }
        hotCornerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}
