import SwiftUI
import WebKit

enum Wallpapers {
    /// APLite's default set. The first six are new; the original iDesk gradients stay at the end
    /// so a wallpaper saved by an earlier version still points at a sensible colour scheme.
    static let builtIn: [[Color]] = [
        // Midnight glass: APLite's signature blue-green.
        [Color(red: 0.03, green: 0.06, blue: 0.14), Color(red: 0.06, green: 0.24, blue: 0.36), Color(red: 0.10, green: 0.46, blue: 0.48)],
        // Aurora.
        [Color(red: 0.04, green: 0.05, blue: 0.16), Color(red: 0.18, green: 0.10, blue: 0.48), Color(red: 0.08, green: 0.62, blue: 0.50)],
        // Sunset mesh.
        [Color(red: 0.16, green: 0.05, blue: 0.18), Color(red: 0.72, green: 0.20, blue: 0.34), Color(red: 0.98, green: 0.56, blue: 0.28)],
        // Graphite.
        [Color(red: 0.06, green: 0.07, blue: 0.09), Color(red: 0.16, green: 0.18, blue: 0.22), Color(red: 0.30, green: 0.32, blue: 0.38)],
        // Ocean.
        [Color(red: 0.02, green: 0.10, blue: 0.22), Color(red: 0.03, green: 0.34, blue: 0.58), Color(red: 0.24, green: 0.72, blue: 0.80)],
        // Orchid.
        [Color(red: 0.12, green: 0.04, blue: 0.20), Color(red: 0.38, green: 0.16, blue: 0.56), Color(red: 0.78, green: 0.44, blue: 0.76)],
        // Original iDesk gradients.
        [Color(red: 0.06, green: 0.10, blue: 0.22), Color(red: 0.18, green: 0.10, blue: 0.30), Color(red: 0.05, green: 0.22, blue: 0.30)],
        [Color(red: 0.95, green: 0.45, blue: 0.30), Color(red: 0.55, green: 0.18, blue: 0.45), Color(red: 0.15, green: 0.10, blue: 0.35)],
        [Color(red: 0.05, green: 0.25, blue: 0.20), Color(red: 0.10, green: 0.45, blue: 0.40), Color(red: 0.02, green: 0.12, blue: 0.18)],
        [Color(red: 0.20, green: 0.45, blue: 0.85), Color(red: 0.45, green: 0.30, blue: 0.85), Color(red: 0.10, green: 0.20, blue: 0.50)],
        [Color(red: 0.12, green: 0.12, blue: 0.14), Color(red: 0.22, green: 0.22, blue: 0.26), Color(red: 0.08, green: 0.08, blue: 0.10)],
    ]
    /// A live manifest can replace the palettes with data, without shipping new native code.
    static var all: [[Color]] { LiveUpdate.wallpaperColors ?? builtIn }
    static var count: Int { all.count }
}

/// The whole UI on the external display.
struct DesktopView: View {
    @ObservedObject var model: DesktopModel

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                WallpaperView(index: model.wallpaper, image: model.customWallpaper,
                              blur: CGFloat(model.wallpaperBlur), performance: model.performanceMode)
                    .frame(width: geo.size.width, height: geo.size.height)

                DesktopIconsView(model: model, cursor: model.cursor)

                if model.showWidgets {
                    DesktopWidgetsView(model: model, cursor: model.cursor)
                }

                // Sticky notes lie on the desktop, under the windows.
                StickiesView(model: model, cursor: model.cursor)

                ForEach(model.windows) { w in
                    WindowView(window: w, focused: w.id == model.focusedID, cursor: model.cursor)
                }

                if let ghost = model.closingWindow {
                    ClosingWindowView(ghost: ghost)
                }

                StickiesView(model: model, cursor: model.cursor, floating: true)

                if let f = model.fillSuggestion {
                    FillSuggestionView(model: model, cursor: model.cursor, suggestion: f)
                }

                if let r = model.snapPreview {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.5), lineWidth: 2))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                }

                if model.showTilePicker {
                    TilePickerView(model: model)
                }

                if model.showLauncher {
                    LauncherView(model: model, cursor: model.cursor)
                }

                if model.showSpotlight {
                    SpotlightView(model: model, cursor: model.cursor)
                }

                if model.showClipboard {
                    ClipboardPanelView(model: model, cursor: model.cursor)
                }

                if model.showDownloads {
                    DownloadsPanelView(model: model, cursor: model.cursor)
                }

                if model.showTaskManager {
                    TaskManagerView(model: model, cursor: model.cursor)
                }

                if model.showEmoji {
                    EmojiPanelView(model: model, cursor: model.cursor)
                }

                if model.taskbarVisible {
                    TaskbarView(model: model, cursor: model.cursor)
                        .frame(width: geo.size.width, height: Layout.taskbar)
                        .offset(y: geo.size.height - Layout.taskbar)
                        .transition(.move(edge: .bottom))
                }

                if let preview = model.taskPreview, model.taskbarVisible {
                    TaskPreviewView(preview: preview, screenWidth: geo.size.width, taskbarTop: model.taskbarTop)
                }

                if let switcher = model.switcher {
                    SwitcherView(model: model, switcher: switcher)
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                if let recents = model.recents {
                    RecentsView(model: model, recents: recents, cursor: model.cursor)
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                if model.showQuickPanel {
                    QuickPanelView(model: model, cursor: model.cursor)
                }

                if let banner = model.banner {
                    NotificationCard(notification: banner)
                        .frame(width: model.bannerRect.width, height: model.bannerRect.height)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 14, y: 4)
                        .offset(x: model.bannerRect.minX, y: model.bannerRect.minY)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if model.showShortcuts {
                    ShortcutsView()
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                if let menu = model.contextMenu {
                    ContextMenuView(menu: menu, cursor: model.cursor)
                }

                if let url = model.quickLook {
                    Color.black.opacity(0.35)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .allowsHitTesting(false)
                    QuickLookView(url: url, rect: model.quickLookRect)
                }

                if let icon = model.iconDrag {
                    DraggedIconView(shortcut: icon, cursor: model.cursor)
                }

                if let toast = model.toast {
                    Text(toast)
                        .font(.system(size: 14, weight: .medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                        .frame(maxWidth: min(560, geo.size.width - 32))
                        .padding(.top, 24)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        .allowsHitTesting(false)
                }

                if let shot = model.screenshotPreview {
                    ScreenshotPreviewView(preview: shot, rect: model.screenshotPreviewRect,
                                          hovered: model.screenshotPreviewRect.contains(model.cursor.position))
                }

                if let c = model.capture {
                    CaptureOverlayView(state: c, size: geo.size)
                }

                if let p = model.laser {
                    LaserDot(point: p)
                }

                if model.showScreenSaver {
                    ScreenSaverView(size: geo.size, wallpaperIndex: model.wallpaper,
                                    wallpaper: model.customWallpaper, wallpaperBlur: model.wallpaperBlur,
                                    performance: model.performanceMode)
                        .transition(.opacity)
                }

                if model.isLocked {
                    LockScreenView(model: model, size: geo.size).transition(.opacity)
                }

                CursorView(cursor: model.cursor)
                    .opacity(model.cursor.isHidden || model.isLocked || model.showScreenSaver ? 0 : 1)

                MediaHUDView(size: geo.size)

                NightFilterView(mode: NightFilter.mode)
                    .frame(width: geo.size.width, height: geo.size.height)

                if model.externalBrightness < 0.99 {
                    Color.black.opacity(1 - model.externalBrightness)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .onAppear { model.screenSize = geo.size }
            .onChange(of: geo.size) { _, newSize in model.screenSize = newSize }
        }
        .ignoresSafeArea()
        // No allowsHitTesting(false) here: it disables interaction on a parent view, and UIKit then ignores
        // actions inside guest apps (see GuestWindowHost). The external display receives no touches anyway.
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }
}

struct WallpaperView: View {
    let index: Int
    var image: UIImage?
    var performance = false
    /// Softens a photo (Settings → Wallpaper → Blur). Gradients ignore it.
    var blur: CGFloat = 0
    var watermark = true

    var body: some View {
        if index == DynamicWallpaper.index {
            TimelineView(.periodic(from: .now, by: 300)) { ctx in
                LinearGradient(colors: DynamicWallpaper.colors(at: ctx.date), startPoint: .topLeading, endPoint: .bottomTrailing)
                    .animation(.easeInOut(duration: 2), value: ctx.date)
            }
        } else if index < 0, let image {
            // Scale a little past the frame before blurring so the edges never turn transparent.
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .scaleEffect(1 + blur / 160)
                .blur(radius: blur, opaque: true)
                .clipped()
        } else {
            let colors = Wallpapers.all[max(0, index) % Wallpapers.count]
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                // Soft light blobs give the flat gradients a mesh-glass depth without image assets.
                if !performance {
                    RadialGradient(colors: [colors[min(2, colors.count - 1)].opacity(0.55), .clear],
                                   center: .topTrailing, startRadius: 40, endRadius: 900)
                        .blendMode(.screen)
                    RadialGradient(colors: [colors[min(1, colors.count - 1)].opacity(0.35), .clear],
                                   center: .bottomLeading, startRadius: 20, endRadius: 760)
                        .blendMode(.screen)
                }
                if watermark {
                    Text(verbatim: APLite.name)
                        .font(.system(size: 96, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.06))
                }
            }
            .animation(.easeInOut(duration: 0.4), value: index)
        }
    }
}

struct AppIcon: View {
    let shortcut: Shortcut
    let size: CGFloat

    var body: some View {
        if let asset = shortcut.asset, let image = UIImage(named: asset) {
            Image(uiImage: image)
                .resizable()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
        } else if let icon = shortcut.app?.icon ?? (shortcut.webApp ? WebApps.shared.icon(for: shortcut.url) : nil) {
            Image(uiImage: icon)
                .resizable()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [Color(hue: shortcut.hue, saturation: 0.65, brightness: 0.95),
                                          Color(hue: shortcut.hue, saturation: 0.8, brightness: 0.65)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Image(systemName: shortcut.symbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
    }
}

// MARK: - Desktop icons

private struct DesktopIconsView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var cursor: CursorModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Where a dragged icon would land.
            if let slot = model.iconDropSlot {
                let r = model.iconRect(slot)
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
            }
            ForEach(model.desktopLayout, id: \.slot) { entry in
                let s = entry.item, r = model.iconRect(entry.slot)
                let hovered = r.contains(cursor.position) && model.topWindow(at: cursor.position) == nil
                let selected = model.selectedIcon == entry.slot
                let dragged = model.iconDrag.map { DesktopModel.key(of: $0) == DesktopModel.key(of: s) } ?? false
                let k = DesktopModel.iconScale(model.iconSize)
                VStack(spacing: 6 * k) {
                    AppIcon(shortcut: s, size: (48 * k).rounded())
                    Text(s.name)
                        .font(.system(size: (12 * k).rounded(), weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.8), radius: 2)
                }
                .frame(width: r.width, height: r.height)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.35) : hovered ? Color.white.opacity(0.1) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1))
                .opacity(dragged ? 0.35 : 1)
                .offset(x: r.minX, y: r.minY)
            }
        }
    }
}

/// The icon being dragged (from the desktop, the app menu or Files), under the pointer.
private struct DraggedIconView: View {
    let shortcut: Shortcut
    @ObservedObject var cursor: CursorModel

    var body: some View {
        VStack(spacing: 4) {
            AppIcon(shortcut: shortcut, size: 48)
            Text(shortcut.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.8), radius: 2)
        }
        .frame(width: Layout.iconCell.width)
        .opacity(0.85)
        .offset(x: cursor.position.x - Layout.iconCell.width / 2, y: cursor.position.y - 30)
        .allowsHitTesting(false)
    }
}

/// A lightweight stand-in for a window that is closing: it flies from the window's frame back
/// to its dock icon while the real window (and its web view / guest app) is already gone.
private struct ClosingWindowView: View {
    let ghost: DesktopModel.ClosingWindow
    @State private var collapsed = false

    var body: some View {
        let w = collapsed ? 52 : ghost.from.width
        let h = collapsed ? 52 : ghost.from.height
        let iconSide: CGFloat = collapsed ? 30 : min(64, w * 0.32)
        ZStack {
            RoundedRectangle(cornerRadius: collapsed ? 16 : 10, style: .continuous)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: collapsed ? 16 : 10, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
            if let icon = ghost.icon {
                Image(uiImage: icon).resizable().frame(width: iconSide, height: iconSide)
                    .clipShape(RoundedRectangle(cornerRadius: iconSide * 0.24, style: .continuous))
            } else {
                Image(systemName: ghost.symbol)
                    .font(.system(size: collapsed ? 20 : 34, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            if !collapsed {
                Text(ghost.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .offset(y: h / 2 - 26)
            }
        }
        .frame(width: w, height: h)
        .position(x: collapsed ? ghost.to.midX : ghost.from.midX,
                  y: collapsed ? ghost.to.midY : ghost.from.midY)
        .scaleEffect(collapsed ? 0.92 : 1)
        .opacity(collapsed ? 0 : 0.96)
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeIn(duration: 0.24)) { collapsed = true } }
    }
}

// MARK: - Windows

private struct WindowView: View {
    static func shadowRadius(focused: Bool) -> CGFloat {
        DesktopModel.shared.performanceMode ? (focused ? 8 : 3) : (focused ? 24 : 10)
    }

    @ObservedObject var window: DeskWindow
    @ObservedObject private var browsing = Browsing.shared      // the bookmarks bar comes and goes with bookmarks
    let focused: Bool
    let cursor: CursorModel

    var body: some View {
        let f = window.frame
        let radius: CGFloat = window.isFullscreen ? 0 : window.isMaximized ? 6 : 10
        VStack(spacing: 0) {
            if !window.isFullscreen {
                TitleBar(title: window.title, focused: focused, frame: f, cursor: cursor,
                         tabs: window.showsTabs ? window.tabs.indices.map { window.title(ofTab: $0) } : nil,
                         activeTab: window.activeTab, keepOnTop: window.keepOnTop)
                    .frame(height: Layout.titleBar)
                if window.showsAddressBar {
                    AddressBar(window: window, focused: focused, cursor: cursor)
                        .frame(height: Layout.addressBar)
                }
                if window.showsBookmarksBar {
                    BookmarksBar(frame: f, focused: focused, cursor: cursor)
                        .frame(height: Layout.bookmarksBar)
                }
            }
            if let guest = window.guestWindow {
                GuestWindowHost(guest: guest, hidden: !window.isShown, area: window.guestRect) { on in window.onFullscreen?(on) }
            } else if let web = window.webView {
                WebViewHost(webView: web).id(ObjectIdentifier(web))     // another tab: another web view
                    .overlay(alignment: .topTrailing) {
                        if let q = window.findQuery { FindBar(query: q, count: window.findCount, index: window.findIndex) }
                    }
            }
        }
        .frame(width: f.width, height: f.height)
        .background(Color(white: 0.1), ignoresSafeAreaEdges: [])
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(focused ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.12),
                        lineWidth: window.isFullscreen ? 0 : 1)
        )
        .shadow(color: .black.opacity(focused ? 0.5 : 0.25),
                radius: WindowView.shadowRadius(focused: focused), y: 8)
        .offset(x: f.minX, y: f.minY)
        .opacity(window.isShown ? 1 : 0)   // keep the web view alive while minimized or on another workspace
        .transition(.scale(scale: 0.88, anchor: .center).combined(with: .opacity))
    }
}

/// Find in page: what is typed, whether it is on the page, and the keys.
private struct FindBar: View {
    let query: String
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            Group {
                if query.isEmpty { Text("Find in page").foregroundStyle(.secondary) }
                else { Text(verbatim: query) + Text(verbatim: "|").foregroundColor(.accentColor) }
            }
            .frame(minWidth: 140, alignment: .leading)
            if !query.isEmpty {
                if count == 0 { Text("Not found").foregroundStyle(.red) }
                else { Text("\(index) of \(count)").foregroundStyle(.secondary).monospacedDigit() }
            }
            Text("Enter: next · Esc: close").foregroundStyle(.secondary).font(.system(size: 11))
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .padding(10)
        .allowsHitTesting(false)
    }
}

private struct TitleBar: View {
    let title: String
    let focused: Bool
    let frame: CGRect
    let cursor: CursorModel
    /// Tab titles of a web window (nil for an app window, which shows its name instead).
    var tabs: [String]? = nil
    var activeTab = 0
    var keepOnTop = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: focused ? [Color(white: 0.26), Color(white: 0.18)]
                                           : [Color(white: 0.18), Color(white: 0.13)],
                           startPoint: .top, endPoint: .bottom)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(focused ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.06))
                    .frame(height: 1)
            }
            if keepOnTop {
                Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 10)
            }
            HStack {
                TitleButtons(frame: frame, focused: focused, cursor: cursor)
                Spacer()
            }
            .padding(.leading, 12)
            .frame(maxHeight: .infinity)
            if let tabs {
                TabStrip(titles: tabs, active: activeTab, focused: focused, frame: frame, cursor: cursor)
            } else {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(focused ? .primary : .secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 90)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// A browser window's tabs, as in a desktop browser: the one shown is lighter, × closes, + opens a new one.
private struct TabStrip: View {
    let titles: [String]
    let active: Int
    let focused: Bool
    let frame: CGRect
    @ObservedObject var cursor: CursorModel

    var body: some View {
        let n = titles.count, p = cursor.position
        ZStack(alignment: .topLeading) {
            ForEach(titles.indices, id: \.self) { i in
                let r = Layout.tabRect(i, count: n, in: frame)
                let hovered = r.contains(p)
                let closeHovered = Layout.tabCloseRect(i, count: n, in: frame).insetBy(dx: -3, dy: -3).contains(p)
                HStack(spacing: 6) {
                    Text(titles[i]).font(.system(size: 12, weight: i == active ? .semibold : .regular)).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.white.opacity(closeHovered ? 0.25 : 0)))
                        .opacity(i == active || hovered ? 1 : 0)
                }
                .padding(.leading, 10).padding(.trailing, 4)
                .frame(width: r.width, height: r.height)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(i == active ? Color.white.opacity(focused ? 0.16 : 0.1) : hovered ? Color.white.opacity(0.07) : .clear))
                .foregroundStyle(Color.white.opacity(i == active ? 1 : 0.62))
                .offset(x: r.minX - frame.minX, y: r.minY - frame.minY)
            }
            let plus = Layout.newTabRect(count: n, in: frame)
            Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                .frame(width: plus.width, height: plus.height)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(plus.contains(p) ? 0.14 : 0)))
                .offset(x: plus.minX - frame.minX, y: plus.minY - frame.minY)
        }
    }
}

/// A web window's back / forward / reload buttons and address field. Clicking the field (or ⌘L) starts typing:
/// keys, the iPhone's compose field and paste go into it, Enter opens the address, Esc cancels.
private struct AddressBar: View {
    @ObservedObject var window: DeskWindow
    let focused: Bool
    @ObservedObject var cursor: CursorModel
    @ObservedObject private var browsing = Browsing.shared

    var body: some View {
        let f = window.frame, p = cursor.position
        HStack(spacing: 4) {
            button("chevron.left", enabled: window.canGoBack, hovered: Layout.backButton(in: f).contains(p))
            button("chevron.right", enabled: window.canGoForward, hovered: Layout.forwardButton(in: f).contains(p))
            button(window.isLoading ? "xmark" : "arrow.clockwise", enabled: true, hovered: Layout.reloadButton(in: f).contains(p))
            field(hovered: Layout.addressField(in: f).contains(p))
                .padding(.leading, 4)
            // ☆ bookmark (web pages only)
            let url = window.webView?.url
            let marked = url.map(browsing.isBookmarked) ?? false
            Image(systemName: marked ? "star.fill" : "star")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(marked ? Color.yellow : (Browsing.isWebPage(url) ? Color.primary : Color.secondary.opacity(0.4)))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(Layout.bookmarkButton(in: f).contains(p) && Browsing.isWebPage(url) ? Color.white.opacity(0.12) : .clear))
            button("ellipsis", enabled: true, hovered: Layout.browserMenuButton(in: f).contains(p))
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // Not into the safe area: near the top of the display (a window snapped or maximized) the background
        // would grow upward over the title bar and hide its buttons and tabs.
        .background(focused ? Color(white: 0.17) : Color(white: 0.13), ignoresSafeAreaEdges: [])
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }

    private func button(_ symbol: String, enabled: Bool, hovered: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.5))
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovered && enabled ? Color.white.opacity(0.12) : .clear))
    }

    private func field(hovered: Bool) -> some View {
        let editing = window.addressDraft != nil
        return HStack(spacing: 6) {
            Image(systemName: window.currentURL.scheme == "https" ? "lock.fill" : "globe")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if let draft = window.addressDraft {
                if draft.isEmpty {
                    Text("Type an address or search").foregroundStyle(.secondary)
                        + Text(verbatim: "|").foregroundColor(.accentColor)
                } else {
                    Text(verbatim: draft) + Text(verbatim: "|").foregroundColor(.accentColor)
                }
            } else {
                Text(verbatim: Self.shown(window.currentURL)).foregroundStyle(.white.opacity(focused ? 0.85 : 0.6))
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12.5))
        .lineLimit(1)
        .truncationMode(.head)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(editing ? Color.black.opacity(0.35) : hovered ? Color.white.opacity(0.1) : Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(editing ? Color.accentColor : .clear, lineWidth: 1.5))
    }

    /// The address without "https://" and a trailing slash, as browsers show it.
    private static func shown(_ url: URL) -> String {
        var s = url.absoluteString
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        if s.hasSuffix("/") { s.removeLast() }
        return s
    }
}

/// The bookmarks under the address bar, as in Chrome: click opens one in the tab, right click for more, » for the
/// ones that don't fit. Positions come from Layout.bookmarkItems, which clicks use too.
private struct BookmarksBar: View {
    let frame: CGRect
    let focused: Bool
    @ObservedObject var cursor: CursorModel
    @ObservedObject private var browsing = Browsing.shared

    var body: some View {
        let marks = browsing.bookmarks
        let layout = Layout.bookmarkItems(marks.map(\.title), in: frame)
        ZStack(alignment: .topLeading) {
            ForEach(Array(layout.items.enumerated()), id: \.offset) { i, r in
                item(marks[i], hovered: r.contains(cursor.position))
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX - frame.minX, y: r.minY - frame.minY - Layout.titleBar - Layout.addressBar)
            }
            if let more = layout.more {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: more.width, height: more.height)
                    .background(RoundedRectangle(cornerRadius: 6).fill(more.contains(cursor.position) ? Color.white.opacity(0.12) : .clear))
                    .offset(x: more.minX - frame.minX, y: more.minY - frame.minY - Layout.titleBar - Layout.addressBar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(focused ? Color(white: 0.17) : Color(white: 0.13), ignoresSafeAreaEdges: [])
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
        .clipped()
    }

    private func item(_ mark: WebEntry, hovered: Bool) -> some View {
        HStack(spacing: 6) {
            if let icon = DeskWindow.cachedFavicon(mark.url) {
                Image(uiImage: icon).resizable().scaledToFit().frame(width: 14, height: 14).clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 14, height: 14)
            }
            Text(verbatim: mark.title).font(Font(Layout.bookmarkFont)).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(.white.opacity(focused ? 0.9 : 0.65))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovered ? Color.white.opacity(0.12) : .clear))
    }
}

/// Three round buttons; symbols appear when the pointer hovers (like macOS).
private struct TitleButtons: View {
    let frame: CGRect
    let focused: Bool
    @ObservedObject var cursor: CursorModel

    var body: some View {
        let hovered = Layout.titleButtons(in: frame).contains(cursor.position)
        let active = focused || hovered
        HStack(spacing: 6) {
            dot(.red, "xmark", 8, active, hovered)
            dot(.yellow, "minus", 8, active, hovered)
            dot(.green, "arrow.up.left.and.arrow.down.right", 7, active, hovered)
        }
    }

    private func dot(_ c: Color, _ symbol: String, _ size: CGFloat, _ active: Bool, _ hovered: Bool) -> some View {
        Circle().fill(active ? c : Color(white: 0.35))
            .frame(width: 16, height: 16)
            .overlay(Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.black.opacity(0.6))
                .opacity(hovered ? 1 : 0))
    }
}

private struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Shows a guest app's window inside a desktop window.
///
/// The guest window stays an independent UIWindow at the origin; here we only "project" its image
/// (portal). Two simpler approaches were tried and both broke:
/// - adding the UIWindow as a subview: the guest's views treat iDesk's window as their own, so alerts and
///   sheets cover the whole screen and the desktop pointer cannot reach them;
/// - adding its layer here: "window → screen" conversions then return desktop positions that do not match
///   the touch coordinates, so SwiftUI buttons ignore taps.
private struct GuestWindowHost: UIViewRepresentable {
    let guest: UIWindow
    let hidden: Bool
    /// Where the app is drawn inside the window (narrower than the window when maximized, see DeskWindow.guestRect).
    let area: CGRect
    /// The app wants landscape (fullscreen video) or no longer does.
    let onLandscape: (Bool) -> Void

    func makeUIView(context: Context) -> GuestContainerView { GuestContainerView() }

    func updateUIView(_ view: GuestContainerView, context: Context) {
        view.guest = guest
        view.isMinimized = hidden
        view.area = area
        view.onLandscape = onLandscape
        view.attach()
    }

    static func dismantleUIView(_ view: GuestContainerView, coordinator: ()) {
        // Closing the desktop window: the guest app stays in the process (code cannot be unloaded), sent to the
        // background by DesktopModel.close.
        view.detach()
    }
}

final class GuestContainerView: UIView {
    var guest: UIWindow?
    var isMinimized = false
    /// Where the app's screen goes in this view; empty: all of it.
    var area: CGRect = .zero { didSet { if area != oldValue { setNeedsLayout() } } }
    var onLandscape: ((Bool) -> Void)?
    private var wantsLandscape = false
    /// One portal per window of the app (main window, overlays…), bottom to top.
    private var portals: [ObjectIdentifier: UIView] = [:]
    /// Windows that fill the app's screen (the main one, full-screen overlays): sized to the desktop window.
    /// Smaller ones (a HUD, a floating button) keep their own frame.
    private var fullScreen = Set<ObjectIdentifier>()
    private var watchdog: Timer?
    /// Shown until the app shows its first window (many apps create it a moment after launching).
    private let spinner = UIActivityIndicatorView(style: .large)

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .black          // the sides of a maximized phone app
        isUserInteractionEnabled = false
        spinner.color = .white
        spinner.hidesWhenStopped = true
        addSubview(spinner)
        let events: [Notification.Name] = [UIWindow.didBecomeVisibleNotification, UIWindow.didBecomeHiddenNotification,
                                           UIWindow.didBecomeKeyNotification,
                                           .GuestRuntimeWindowsChanged]
        for name in events {
            NotificationCenter.default.addObserver(self, selector: #selector(windowsChanged), name: name, object: nil)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func attach() {
        guard let guest, window != nil else { return }
        // GuestRuntime keeps every window of the app below iDesk's own (solid black) window, so nothing of the
        // app shows on the iPhone screen; the user sees the projections here.
        let windows = isMinimized ? [] : GuestRuntime.windowsOfApp(with: guest)
        // Only on a change, so leaving fullscreen with Esc sticks until the app asks again.
        let landscape = GuestRuntime.appWantsLandscape(with: guest)
        if landscape != wantsLandscape {
            wantsLandscape = landscape
            DispatchQueue.main.async { [onLandscape] in onLandscape?(landscape) }
        }
        let screen = area.isEmpty ? bounds : area
        spinner.center = CGPoint(x: screen.midX, y: screen.midY)
        if windows.isEmpty && !isMinimized { spinner.startAnimating() } else { spinner.stopAnimating() }
        let size = screen.size
        var alive = Set<ObjectIdentifier>()
        var ordered: [UIView] = []
        for w in windows {
            let id = ObjectIdentifier(w)
            alive.insert(id)
            if portals[id] == nil, w.frame.size == w.screen.bounds.size || w.frame.size == size {
                fullScreen.insert(id)
            }
            if fullScreen.contains(id), w.frame.size != size || w.frame.origin != .zero {
                w.frame = CGRect(origin: .zero, size: size)
            }
            // hidesSource: do not draw the window at its original place on the iPhone screen.
            if portals[id] == nil { portals[id] = Portal.make(of: w, hidesSource: true) }
            if let portal = portals[id] {
                ordered.append(portal)
                let frame = fullScreen.contains(id) ? screen : w.frame.offsetBy(dx: screen.minX, dy: screen.minY)
                if portal.frame != frame { portal.frame = frame }
            } else if w.layer.superlayer !== layer {
                // No portal available (iOS changed the private API): attach the layer directly and accept coordinate glitches.
                layer.addSublayer(w.layer)
            }
            cancelSafeArea(of: w)
        }
        for (id, portal) in portals where !alive.contains(id) {
            portal.removeFromSuperview()
            portals[id] = nil
            fullScreen.remove(id)
        }
        // Stack the portals like the app's windows; only touch the hierarchy when the order changed.
        if subviews.filter({ ordered.contains($0) }) != ordered || ordered.contains(where: { $0.superview !== self }) {
            ordered.forEach { addSubview($0) }
        }
        if watchdog == nil {
            // Windows shown, hidden or made key, and rotation requests, update at once (see init). A slow check
            // catches what iOS announces nowhere, such as the app swapping its root view controller.
            watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.attach() }
            watchdog?.tolerance = 0.3
        }
    }

    /// A guest window belongs to the iPhone scene, so it gets insets for the notch / home indicator even
    /// though it is shown inside a desktop window. Cancel them with negative safe-area insets until they are 0.
    private func cancelSafeArea(of w: UIWindow) {
        guard let root = w.rootViewController, root.isViewLoaded else { return }
        let extra = root.view.safeAreaInsets
        guard extra != .zero else { return }
        let a = root.additionalSafeAreaInsets
        root.additionalSafeAreaInsets = UIEdgeInsets(top: a.top - extra.top, left: a.left - extra.left,
                                                     bottom: a.bottom - extra.bottom, right: a.right - extra.right)
    }

    /// Several events in a row (an app showing two windows at once) update once.
    private var updatePending = false
    @objc private func windowsChanged() {
        guard watchdog != nil, !updatePending else { return }
        updatePending = true
        DispatchQueue.main.async { [weak self] in
            self?.updatePending = false
            self?.attach()
        }
    }

    func detach() {
        watchdog?.invalidate()
        watchdog = nil
        portals.values.forEach { $0.removeFromSuperview() }
        portals = [:]
        fullScreen = []
        guard let guest else { return }
        for w in GuestRuntime.windowsOfApp(with: guest) where w.layer.superlayer === layer { w.layer.removeFromSuperlayer() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attach()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attach()
    }
}

// MARK: - Taskbar (floating dock)

/// Three floating glass pills: controls on the left, app icons centred, the tray on the right.
/// Every rect comes from DesktopModel, so drawing and hit testing cannot drift apart.
private struct TaskbarView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var cursor: CursorModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let p = cursor.position
        let y0 = model.taskbarTop
        let palette = DockPalette(mode: model.dockAppearance, scheme: colorScheme)
        let left = model.leftDockRect
        let right = model.rightDockRect
        // taskLayout walks the pinned apps and every open window. Compute it once per redraw
        // instead of once for the empty check, once for the ForEach and once inside dockRect.
        let items = model.taskLayout
        let dock = Self.dockRect(from: items, height: model.dockHeight, y: model.dockY)

        ZStack(alignment: .topLeading) {
            DockGlass(rect: left, y0: y0, palette: palette, opacity: model.dockOpacity) {
                ZStack(alignment: .topLeading) {
                    control("circle.grid.3x3.fill", rect: model.startButtonRect, in: left, palette: palette,
                            active: model.showLauncher, hovered: model.startButtonRect.contains(p), size: 17)
                    control("magnifyingglass", rect: model.navButtonRect(.search), in: left, palette: palette,
                            active: model.showSpotlight, hovered: model.navButtonRect(.search).contains(p))
                    control("square.stack.3d.up", rect: model.navButtonRect(.recents), in: left, palette: palette,
                            active: model.recents != nil, hovered: model.navButtonRect(.recents).contains(p))
                    control("house", rect: model.navButtonRect(.home), in: left, palette: palette,
                            active: false, hovered: model.navButtonRect(.home).contains(p))
                    control("chevron.backward", rect: model.navButtonRect(.back), in: left, palette: palette,
                            active: false, hovered: model.navButtonRect(.back).contains(p))
                    if model.workspacesEnabled {
                        ForEach(0..<DesktopModel.workspaceCount, id: \.self) { n in
                            workspace(n, in: left, palette: palette, p: p)
                        }
                    }
                }
            }

            if !items.isEmpty {
                DockGlass(rect: dock, y0: y0, palette: palette, opacity: model.dockOpacity) {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            DockItem(entry: item.entry, rect: item.rect, container: dock,
                                     hovered: item.rect.contains(p),
                                     magnification: magnification(for: item.rect, at: p),
                                     palette: palette, focusedID: model.focusedID)
                        }
                    }
                }
            }

            DockGlass(rect: right, y0: y0, palette: palette, opacity: model.dockOpacity) {
                ZStack(alignment: .topLeading) {
                    if let r = model.recordButtonRect {
                        RecordButton(hovered: r.contains(p))
                            .frame(width: r.width, height: r.height)
                            .offset(x: r.minX - right.minX, y: r.minY - right.minY)
                    }
                    if let r = model.downloadsButtonRect {
                        DownloadsButton(hovered: r.contains(p), open: model.showDownloads)
                            .frame(width: r.width, height: r.height)
                            .offset(x: r.minX - right.minX, y: r.minY - right.minY)
                    }
                    let tm = model.taskManagerButtonRect
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(model.showTaskManager ? palette.active : palette.primary)
                        .frame(width: tm.width, height: tm.height)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(model.showTaskManager ? palette.active.opacity(0.22)
                                  : tm.contains(p) ? palette.hover : .clear))
                        .offset(x: tm.minX - right.minX, y: tm.minY - right.minY)

                    TrayView(palette: palette)
                        .frame(width: model.trayRect.width, height: model.trayRect.height)
                        .offset(x: model.trayRect.minX - right.minX, y: model.trayRect.minY - right.minY)
                    showDesktop(in: right, palette: palette, hovered: model.showDesktopRect.contains(p))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private static func dockRect(from items: [(entry: DesktopModel.TaskEntry, rect: CGRect)],
                                 height: CGFloat, y: CGFloat) -> CGRect {
        guard let first = items.first, let last = items.last else { return .zero }
        let pad = Layout.dockPadding
        return CGRect(x: first.rect.minX - pad, y: y,
                      width: last.rect.maxX - first.rect.minX + pad * 2, height: height)
    }

    /// Apple-style magnification: icons near the pointer grow, the ones further away stay put.
    private func magnification(for rect: CGRect, at p: CGPoint) -> CGFloat {
        guard model.dockMagnification, !model.performanceMode, p.y >= model.dockY - 24 else { return 1 }
        let reach = max(96, rect.width * 2.6)
        let amount = max(0, 1 - abs(p.x - rect.midX) / reach)
        return 1 + 0.28 * amount
    }

    private func control(_ symbol: String, rect: CGRect, in container: CGRect, palette: DockPalette,
                         active: Bool, hovered: Bool, size: CGFloat = 15) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(palette.primary.opacity(active || hovered ? 1 : 0.82))
            .frame(width: rect.width, height: rect.height)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(active ? palette.active.opacity(0.26) : hovered ? palette.hover : .clear))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(active ? palette.active.opacity(0.45) : .clear, lineWidth: 1))
            .offset(x: rect.minX - container.minX, y: rect.minY - container.minY)
    }

    private func workspace(_ n: Int, in container: CGRect, palette: DockPalette, p: CGPoint) -> some View {
        let r = model.workspaceCellRect(n)
        let current = n == model.workspace
        let used = model.windows.contains { $0.workspace == n }
        return VStack(spacing: 1) {
            Text(verbatim: "\(n + 1)")
                .font(.system(size: 11, weight: current ? .bold : .medium).monospacedDigit())
            Circle()
                .fill(used ? palette.primary.opacity(current ? 0.9 : 0.45) : .clear)
                .frame(width: 3, height: 3)
        }
        .foregroundStyle(current ? palette.primary : palette.secondary)
        .frame(width: r.width, height: r.height)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(current ? palette.hover : r.contains(p) ? palette.hover.opacity(0.6) : .clear))
        .offset(x: r.minX - container.minX, y: r.minY - container.minY)
    }

    private func showDesktop(in container: CGRect, palette: DockPalette, hovered: Bool) -> some View {
        let r = model.showDesktopRect
        return VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule().fill(palette.secondary.opacity(hovered ? 0.9 : 0.45))
                    .frame(width: 3, height: 5)
            }
        }
        .frame(width: r.width, height: r.height)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(hovered ? palette.hover : .clear))
        .offset(x: r.minX - container.minX, y: r.minY - container.minY)
    }
}

/// The glass behind one pill: thin material, a tint that follows the appearance setting, a fine
/// border and a soft shadow. Content is positioned in screen coordinates, then the whole pill is
/// moved into the taskbar band.
private struct DockGlass<Content: View>: View {
    let rect: CGRect
    let y0: CGFloat
    let palette: DockPalette
    let opacity: Double
    let content: Content

    init(rect: CGRect, y0: CGFloat, palette: DockPalette, opacity: Double,
         @ViewBuilder content: () -> Content) {
        self.rect = rect
        self.y0 = y0
        self.palette = palette
        self.opacity = opacity
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: rect.height * 0.42, style: .continuous)
        ZStack(alignment: .topLeading) { content }
            .frame(width: rect.width, height: rect.height, alignment: .topLeading)
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(palette.fill.opacity(opacity))
                }
            }
            .overlay(shape.strokeBorder(palette.stroke, lineWidth: 1))
            .overlay(alignment: .top) {
                Capsule()
                    .fill(palette.primary.opacity(0.16))
                    .frame(width: rect.width * 0.55, height: 1)
                    .padding(.top, 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            .offset(x: rect.minX, y: rect.minY - y0)
            .allowsHitTesting(false)
    }
}

/// One app in the centre dock: a pinned app or an open window, with a running indicator and a
/// name tag on hover. The icon magnifies while the pointer is near it.
private struct DockItem: View {
    let entry: DesktopModel.TaskEntry
    let rect: CGRect
    let container: CGRect
    let hovered: Bool
    let magnification: CGFloat
    let palette: DockPalette
    let focusedID: UUID?

    var body: some View {
        let window = entry.window
        let active = window.map { $0.id == focusedID && !$0.isMinimized } ?? false
        let title = window?.title ?? pinnedName
        ZStack(alignment: .bottom) {
            if hovered, !title.isEmpty {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(palette.stroke, lineWidth: 1))
                    .fixedSize()
                    .offset(y: -rect.height - 7)
                    .allowsHitTesting(false)
            }
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: rect.width * 0.28, style: .continuous)
                    .fill(hovered ? palette.hover : .clear)
                    .overlay(RoundedRectangle(cornerRadius: rect.width * 0.28, style: .continuous)
                        .stroke(palette.primary.opacity(hovered ? 0.16 : 0), lineWidth: 1))
                    .frame(width: rect.width * 0.96, height: rect.width * 0.96)
                if let window {
                    windowIcon(window)
                } else if case let .pinned(shortcut, _) = entry {
                    AppIcon(shortcut: shortcut, size: rect.width * 0.72)
                }
                if window != nil {
                    Capsule()
                        .fill(active ? palette.active : palette.primary.opacity(0.55))
                        .frame(width: active ? 12 : 5, height: 3)
                        .offset(y: -2)
                }
            }
            .frame(width: rect.width, height: rect.height, alignment: .bottom)
            .scaleEffect(magnification, anchor: .bottom)
        }
        .frame(width: rect.width, height: rect.height, alignment: .bottom)
        .offset(x: rect.minX - container.minX, y: rect.minY - container.minY)
        .opacity(window?.isMinimized == true ? 0.55 : 1)
        .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
    }

    private var pinnedName: String {
        if case let .pinned(shortcut, _) = entry { return shortcut.name }
        return ""
    }

    @ViewBuilder
    private func windowIcon(_ w: DeskWindow) -> some View {
        let side = rect.width * 0.72
        if let icon = w.icon {
            Image(uiImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: side * 0.24, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
        } else {
            RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [palette.active.opacity(0.9), palette.active.opacity(0.5)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: side, height: side)
                .overlay(Image(systemName: w.symbol)
                    .font(.system(size: side * 0.45, weight: .semibold))
                    .foregroundStyle(.white))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
        }
    }
}

/// System tray: memory, network, battery, time and date.
private struct TrayView: View {
    @ObservedObject private var network = NetworkStatus.shared
    let palette: DockPalette

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { ctx in
            HStack(spacing: 10) {
                // Memory: every app runs inside iDesk; orange / red when iOS is about to close it.
                let memory = MemoryStatus.level
                HStack(spacing: 4) {
                    Image(systemName: "memorychip")
                    Text(verbatim: MemoryStatus.format(MemoryStatus.used)).font(.system(size: 12).monospacedDigit())
                }
                .foregroundStyle(memory == .critical ? Color.red : memory == .low ? Color.orange : palette.primary)
                Image(systemName: network.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(network.kind == .offline ? palette.secondary : palette.primary)
                // Heat: shown only when the iPhone is hot enough to slow down.
                let heat = ProcessInfo.processInfo.thermalState
                if heat == .serious || heat == .critical {
                    Image(systemName: "thermometer.high")
                        .foregroundStyle(heat == .critical ? Color.red : Color.orange)
                }
                let level = UIDevice.current.batteryLevel
                if level >= 0 {
                    HStack(spacing: 4) {
                        Image(systemName: batterySymbol(level, UIDevice.current.batteryState))
                        Text("\(Int((level * 100).rounded()))%").font(.system(size: 12).monospacedDigit())
                    }
                    .foregroundStyle(level <= 0.2 && UIDevice.current.batteryState == .unplugged ? Color.orange : palette.primary)
                }
                VStack(alignment: .trailing, spacing: 1) {
                    Text(ctx.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                    Text(ctx.date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year()))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(palette.secondary)
                }
            }
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func batterySymbol(_ level: Float, _ state: UIDevice.BatteryState) -> String {
        if state == .charging || state == .full { return "battery.100.bolt" }
        switch level {
        case 0.875...: return "battery.100"
        case 0.625...: return "battery.75"
        case 0.375...: return "battery.50"
        case 0.125...: return "battery.25"
        default: return "battery.0"
        }
    }
}

// MARK: - App menu

private struct LauncherView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var cursor: CursorModel

    var body: some View {
        let r = model.launcherRect
        ZStack(alignment: .topLeading) {
            Text("Apps")
                .font(.system(size: 15, weight: .semibold))
                .offset(x: Layout.launcherPadding + 4, y: Layout.launcherPadding + 6)

            // Search: typing on the keyboard while the menu is open goes here.
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                if model.launcherQuery.isEmpty {
                    Text("Type to search").foregroundStyle(.secondary)
                } else {
                    Text(verbatim: model.launcherQuery) + Text(verbatim: "|").foregroundColor(.accentColor)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(width: r.width - Layout.launcherPadding * 2, height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            .offset(x: Layout.launcherPadding, y: Layout.launcherPadding + 34)

            if model.launcherItems.isEmpty {
                // Nothing matches: Enter (or a click here) searches the web for what was typed.
                let t = model.launcherSearchRect
                HStack(spacing: 8) {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                    Text("Search the web for “\(model.launcherQuery)”").lineLimit(1)
                    Spacer(minLength: 0)
                    Text("Enter ↵").foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .frame(width: t.width, height: t.height)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(t.contains(cursor.position) ? 0.16 : 0.08)))
                .offset(x: t.minX - r.minX, y: t.minY - r.minY)
            }

            // Section titles when the Recent row shows.
            if !model.launcherRecents.isEmpty {
                let first = model.launcherItemRect(0), all = model.launcherItemRect(model.launcherRecents.count)
                Text("Recent").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    .offset(x: Layout.launcherPadding + 4, y: first.minY - r.minY - Layout.launcherSectionTitle + 4)
                Text("All apps").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    .offset(x: Layout.launcherPadding + 4, y: all.minY - r.minY - Layout.launcherSectionTitle + 4)
            }

            if model.launcherShowsAppsHint {
                let t = model.launcherAppsHintRect
                HStack(spacing: 8) {
                    Image(systemName: "shippingbox").foregroundStyle(.secondary)
                    Text("No iOS apps yet: add them from IPA files").lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(width: t.width, height: t.height)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(t.contains(cursor.position) ? 0.16 : 0.06)))
                .offset(x: t.minX - r.minX, y: t.minY - r.minY)
            }

            ForEach(Array(model.launcherItems.enumerated()), id: \.offset) { i, s in
                let t = model.launcherItemRect(i)
                let hovered = t.contains(cursor.position)
                VStack(spacing: 8) {
                    AppIcon(shortcut: s, size: 40)
                    Text(s.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
                .frame(width: t.width, height: t.height)
                .background(RoundedRectangle(cornerRadius: 10).fill(hovered ? Color.white.opacity(0.14) : .clear))
                .offset(x: t.minX - r.minX, y: t.minY - r.minY)
            }
        }
        .frame(width: r.width, height: r.height, alignment: .topLeading)
        .floatingPanel(cornerRadius: 16)
        .offset(x: r.minX, y: r.minY)
    }
}

// MARK: - Alt+Tab switcher

private struct SwitcherView: View {
    @ObservedObject var model: DesktopModel
    let switcher: DesktopModel.Switcher

    var body: some View {
        let windows = switcher.ids.compactMap { id in model.windows.first { $0.id == id } }
        HStack(spacing: 12) {
            ForEach(Array(windows.enumerated()), id: \.element.id) { i, w in
                VStack(spacing: 10) {
                    Group {
                        if let icon = w.icon {
                            Image(uiImage: icon).resizable()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.1))
                                .overlay(Image(systemName: w.symbol).font(.system(size: 26)))
                        }
                    }
                    .frame(width: 56, height: 56)
                    Text(w.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding(12)
                .frame(width: 132, height: 128)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(i == switcher.index ? Color.accentColor.opacity(0.45) : Color.clear))
                .opacity(w.isMinimized ? 0.6 : 1)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
    }
}

// MARK: - Quick panel

/// Opened from the clock: quick toggles, external display brightness and the apps' notifications.
private struct QuickPanelView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var cursor: CursorModel

    var body: some View {
        let r = model.quickPanelRect, p = cursor.position
        ZStack(alignment: .topLeading) {
            TimelineView(.periodic(from: .now, by: 15)) { ctx in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    Text(ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .offset(x: 14, y: 12)

            ForEach(0..<DesktopModel.quickTileCount, id: \.self) { i in
                let t = model.quickTileRect(i)
                let (symbol, label, on) = tile(i)
                VStack(spacing: 6) {
                    Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                    Text(label).font(.system(size: 10.5, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(width: t.width, height: t.height)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(on ? Color.accentColor.opacity(0.75) : Color.white.opacity(t.contains(p) ? 0.18 : 0.1)))
                .offset(x: t.minX - r.minX, y: t.minY - r.minY)
            }

            // Brightness of the external display: − bar +
            let down = model.brightnessDownRect, up = model.brightnessUpRect
            Group {
                roundButton("sun.min", hovered: down.contains(p)).offset(x: down.minX - r.minX, y: down.minY - r.minY)
                roundButton("sun.max.fill", hovered: up.contains(p)).offset(x: up.minX - r.minX, y: up.minY - r.minY)
                let barX = down.maxX + 10, barW = up.minX - 10 - barX
                Capsule().fill(Color.white.opacity(0.12)).frame(width: barW, height: 8)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.85))
                            .frame(width: barW * CGFloat((model.externalBrightness - 0.2) / 0.8), height: 8)
                    }
                    .offset(x: barX - r.minX, y: down.midY - 4 - r.minY)
            }

            // Notifications
            let top = model.notificationsTop
            Text("Notifications").font(.system(size: 13, weight: .semibold))
                .offset(x: 14, y: top + 5 - r.minY)
            if !model.notifications.isEmpty {
                let c = model.clearNotificationsRect
                Text("Clear all").font(.system(size: 12, weight: .medium))
                    .frame(width: c.width, height: c.height)
                    .background(Capsule().fill(Color.white.opacity(c.contains(p) ? 0.2 : 0.1)))
                    .offset(x: c.minX - r.minX, y: c.minY - r.minY)
            } else {
                Text("No notifications").font(.system(size: 12)).foregroundStyle(.secondary)
                    .offset(x: 14, y: top + 34 - r.minY)
            }
            ForEach(Array(model.notifications.prefix(5).enumerated()), id: \.element.id) { i, n in
                let row = model.notificationRect(i)
                NotificationCard(notification: n)
                    .frame(width: row.width, height: row.height)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(row.contains(p) ? 0.14 : 0.07)))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.white.opacity(model.notificationCloseRect(i).contains(p) ? 0.3 : 0.12)))
                            .padding(6)
                            .opacity(row.contains(p) ? 1 : 0)
                    }
                    .offset(x: row.minX - r.minX, y: row.minY - r.minY)
            }
        }
        .frame(width: r.width, height: r.height, alignment: .topLeading)
        .floatingPanel(cornerRadius: 16)
        .offset(x: r.minX, y: r.minY)
    }

    private func tile(_ i: Int) -> (String, LocalizedStringKey, Bool) {
        switch i {
        case 0: return ("moon.fill", "Do not disturb", model.doNotDisturb)
        case 1: return ("dock.arrow.down.rectangle", "Hide taskbar", model.autoHideTaskbar)
        case 2: return ("camera.viewfinder", "Screenshot", false)
        default: return ("gearshape", "Settings", false)
        }
    }

    private func roundButton(_ symbol: String, hovered: Bool) -> some View {
        Image(systemName: symbol).font(.system(size: 14))
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.white.opacity(hovered ? 0.2 : 0.1)))
    }
}

/// One notification: the app's icon, title, text and time.
private struct NotificationCard: View {
    let notification: DeskNotification

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let icon = notification.app?.icon {
                    Image(uiImage: icon).resizable()
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.15))
                        .overlay(Image(systemName: "bell.fill").font(.system(size: 14)))
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(notification.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(notification.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .padding(.trailing, 22)
                }
                if !notification.body.isEmpty {
                    Text(notification.body).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Widgets

/// Desktop widgets: a clock and this month's calendar, top right, behind the windows.
// MARK: - Taskbar preview

/// A picture of a window above its taskbar button, shown while the pointer rests on the button.
private struct TaskPreviewView: View {
    let preview: DesktopModel.TaskPreview
    let screenWidth: CGFloat
    let taskbarTop: CGFloat

    var body: some View {
        let width: CGFloat = 240, height: CGFloat = 170
        let x = min(max(8, preview.anchor.midX - width / 2), screenWidth - width - 8)
        VStack(alignment: .leading, spacing: 6) {
            Text(preview.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            Group {
                if let image = preview.image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Color(white: 0.15)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(8)
        .frame(width: width, height: height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 4)
        .offset(x: x, y: taskbarTop - height - 8)
        .allowsHitTesting(false)
    }
}

// MARK: - Keyboard shortcuts

/// ⌘ + / (or the desktop menu): every shortcut on one panel.
private struct ShortcutsView: View {
    /// The workspace rows show only while workspaces are on.
    var workspaces = UserDefaults.standard.bool(forKey: DesktopModel.Keys.workspaces)

    private var rows: [(String, LocalizedStringKey)] {
        allRows.filter { workspaces || !$0.0.contains("Ctrl + ") || $0.0 == "Ctrl + Tab" }
    }
    private var gestures: [(String, LocalizedStringKey)] {
        allGestures.filter { workspaces || !$0.0.hasPrefix("4 ←") }
    }
    private let allRows: [(String, LocalizedStringKey)] = [
        ("⌘", "App menu (type to search)"),
        ("⌘ + Space", "Spotlight: apps, files, sums, the web"),
        ("⌘ + Tab", "Recent apps"),
        ("⌥ + Tab", "Switch windows"),
        ("⌘ + ← → ↑ ↓", "Snap, maximize, minimize the window"),
        ("⌘ + Ctrl + ← →", "Previous / next workspace"),
        ("⌘ + Ctrl + Shift + ← →", "Move the window to another workspace"),
        ("Esc  ·  ⌥ + ←", "Back"),
        ("⌘ + D", "Show desktop"),
        ("Space", "Quick Look of the file selected in Files"),
        ("⌘ + M  ·  ⌘ + H", "Minimize"),
        ("⌘ + W", "Close the tab or window"),
        ("⌘ + Q", "Close the window with all its tabs"),
        ("⌘ + `", "Next window"),
        ("⌘ + Y", "Bookmarks and history"),
        ("⌘ + F  ·  ⌘ + G", "Find in page  ·  next match"),
        ("⌘ + =  ·  ⌘ + −  ·  ⌘ + 0", "Zoom the page in, out, back to 100 %"),
        ("⌘ + T  ·  ⌘ + N", "New tab  ·  New window"),
        ("⌘ + Shift + T", "Reopen the last closed tab or window"),
        ("⌘ + L", "Address bar"),
        ("Ctrl + Tab", "Next tab"),
        ("⌘ + C / X / V", "Copy / cut / paste"),
        ("⌘ + Shift + V", "Clipboard history"),
        ("⌘ + Shift + 3", "Screenshot of the whole screen"),
        ("⌘ + Shift + 4", "Screenshot of an area or a window"),
        ("⌘ + /", "This list"),
    ]
    private let allGestures: [(String, LocalizedStringKey)] = [
        ("3 ↑", "Recent apps"),
        ("3 ↓", "Home"),
        ("3 ← →", "Next / previous app"),
        ("3 •", "Back"),
        ("4 ← →", "Next / previous workspace"),
        ("4 •", "App menu"),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 28) {
                    column("Keyboard", rows)
                    column("Trackpad (fingers)", gestures)
                }
                // Apple key names; other keyboards' logo key and Alt do the same.
                Text("⌥ is the Option key. On a keyboard without ⌘ and ⌥, use the logo key (or Ctrl) and Alt.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
        }
        .allowsHitTesting(false)
    }

    private func column(_ title: LocalizedStringKey, _ items: [(String, LocalizedStringKey)]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 15, weight: .semibold)).padding(.bottom, 4)
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 12) {
                    Text(verbatim: items[i].0)
                        .font(.system(size: 12, weight: .semibold).monospaced())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.12)))
                        .frame(width: 215, alignment: .leading)
                    Text(items[i].1).font(.system(size: 13))
                }
            }
        }
    }
}

// MARK: - Recent apps

/// Every window as a card with a picture of it, like the iPhone's app switcher: click one to switch to it,
/// its × (or Delete) closes it, "Close all" closes everything.
private struct RecentsView: View {
    @ObservedObject var model: DesktopModel
    let recents: DesktopModel.Switcher
    @ObservedObject var cursor: CursorModel

    var body: some View {
        let count = recents.ids.count
        let p = cursor.position
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.78)
            if count == 0 {
                Text("No recent apps")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: model.desktopArea.width, height: model.desktopArea.height)
            }
            ForEach(Array(recents.ids.enumerated()), id: \.element) { i, id in
                if let w = model.windows.first(where: { $0.id == id }) {
                    let r = model.recentsTileRect(i, of: count)
                    card(w, image: model.thumbnails[id], rect: r, selected: i == recents.index,
                         hovered: r.contains(p), closeHovered: model.recentsCloseRect(i, of: count).contains(p))
                        .offset(x: r.minX, y: r.minY)
                }
            }
            if count > 0 {
                let r = model.recentsCloseAllRect
                Text("Close all")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: r.width, height: r.height)
                    .background(Capsule().fill(Color.white.opacity(r.contains(p) ? 0.28 : 0.16)))
                    .offset(x: r.minX, y: r.minY)
            }
        }
    }

    private func card(_ w: DeskWindow, image: UIImage?, rect r: CGRect, selected: Bool,
                      hovered: Bool, closeHovered: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if let icon = w.icon {
                    Image(uiImage: icon).resizable().frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    Image(systemName: w.symbol).font(.system(size: 14))
                }
                Text(w.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer(minLength: 28)
            }
            .frame(height: Layout.recentsTitle - 6)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.12))
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if let icon = w.icon {
                    Image(uiImage: icon).resizable().frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                } else {
                    Image(systemName: w.symbol).font(.system(size: 40)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .frame(width: r.width, height: r.height)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(selected ? Color(red: 0.12, green: 0.27, blue: 0.5) : Color(white: hovered ? 0.24 : 0.18)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(closeHovered ? 0.35 : 0.14)))
                .padding(.top, 5).padding(.trailing, 4)
        }
        .opacity(w.isMinimized && !selected ? 0.85 : 1)
    }
}

// MARK: - Context menu

private struct ContextMenuView: View {
    let menu: ContextMenu
    @ObservedObject var cursor: CursorModel

    var body: some View {
        let f = menu.frame
        VStack(spacing: 0) {
            ForEach(Array(menu.items.enumerated()), id: \.offset) { i, item in
                if item.isSeparator {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                        .padding(.horizontal, 6)
                        .frame(height: Layout.menuSeparatorHeight)
                } else {
                    let hovered = item.enabled && menu.itemRect(i).contains(cursor.position)
                    HStack(spacing: 10) {
                        Group {
                            if let s = item.symbol { Image(systemName: s) } else { Color.clear }
                        }
                        .frame(width: 18)
                        Text(item.title).font(.system(size: 13))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: Layout.menuItemHeight)
                    .background(RoundedRectangle(cornerRadius: 6).fill(hovered ? Color.accentColor.opacity(0.6) : .clear))
                    .opacity(item.enabled ? 1 : 0.4)
                }
            }
        }
        .padding(Layout.menuPadding)
        .frame(width: f.width, height: f.height, alignment: .top)
        .floatingPanel(cornerRadius: 10, shadow: 16)
        .offset(x: f.minX, y: f.minY)
    }
}

// MARK: - Panels

extension View {
    /// The look of the panels that float over the desktop (app menu, Spotlight, menus…): frosted glass, a thin
    /// light edge and a soft shadow.
    func floatingPanel(cornerRadius r: CGFloat, shadow: CGFloat = 20) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: r, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).stroke(Color.white.opacity(0.13), lineWidth: 1))
            .shadow(color: .black.opacity(0.42), radius: shadow, y: shadow / 3)
    }
}

// MARK: - Pointer

private struct CursorView: View {
    @ObservedObject var cursor: CursorModel

    var body: some View {
        content.opacity(cursor.drawnByViewer ? 0 : 1)
    }

    private var content: some View {
        let p = cursor.position
        // The press bounce must scale around the hot spot itself, and must come BEFORE offset.
        // Scaling the whole thing after moving it drags the pointer toward the screen corner on every click.
        let press: CGFloat = (cursor.isPressed ? 0.85 : 1) * cursor.magnify
        return Group {
            switch cursor.style {
            case .arrow, .grab:
                // Hand-drawn arrow: its tip is at (0,0), so the hot spot = the tip.
                ArrowCursor()
                    .frame(width: 18, height: 26)
                    .scaleEffect(press, anchor: .topLeading)
                    .offset(x: p.x, y: p.y)
            case .pointer:
                // Hand: the index fingertip is near the top, aligned to the hot spot.
                glyph("hand.point.up.left.fill", 24)
                    .scaleEffect(press, anchor: .topLeading)
                    .offset(x: p.x - 6, y: p.y - 2)
            default:
                glyph(symbol, 18).frame(width: 28, height: 28)
                    .scaleEffect(press)
                    .offset(x: p.x - 14, y: p.y - 14)
            }
        }
    }

    private var symbol: String {
        switch cursor.style {
        case .text: return "character.cursor.ibeam"
        case .resizeH: return "arrow.left.and.right"
        case .resizeV: return "arrow.up.and.down"
        case .resizeNWSE: return "arrow.up.left.and.arrow.down.right"
        case .resizeNESW: return "arrow.up.right.and.arrow.down.left"
        case .crosshair: return "plus"
        case .arrow, .pointer, .grab: return "cursorarrow"
        }
    }

    private func glyph(_ name: String, _ size: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 1)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
    }
}

/// Classic arrow pointer, tip at the origin (0,0).
private struct ArrowCursor: View {
    var body: some View {
        ArrowShape()
            .fill(.white)
            .overlay(ArrowShape().stroke(.black, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
    }
}

private struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: 0, y: 17.5))
        p.addLine(to: CGPoint(x: 4.3, y: 13.2))
        p.addLine(to: CGPoint(x: 7.2, y: 20))
        p.addLine(to: CGPoint(x: 10, y: 18.8))
        p.addLine(to: CGPoint(x: 7.2, y: 12.2))
        p.addLine(to: CGPoint(x: 13, y: 12.2))
        p.closeSubpath()
        return p
    }
}

/// `_UIPortalView` (private UIKit API): renders a view's content somewhere else without moving it,
/// even on another display (guest window on the iPhone → desktop; desktop → mirror on the iPhone).
enum Portal {
    static func make(of source: UIView, hidesSource: Bool) -> UIView? {
        guard let cls = NSClassFromString("_UIPortalView") as? UIView.Type else { return nil }
        let portal = cls.init(frame: .zero)
        let setters: [(String, Any)] = [
            ("sourceView", source),
            ("hidesSourceView", hidesSource),
            ("matchesPosition", false),
            ("matchesTransform", false),
            ("matchesAlpha", false),
        ]
        for (key, value) in setters {
            let setter = Selector("set" + key.prefix(1).uppercased() + key.dropFirst() + ":")
            guard portal.responds(to: setter) else { return key == "sourceView" ? nil : portal }
            portal.setValue(value, forKey: key)
        }
        if portal.layer.responds(to: Selector(("setCrossDisplay:"))) {
            portal.layer.setValue(true, forKey: "crossDisplay")
        }
        portal.isUserInteractionEnabled = false
        return portal
    }
}
