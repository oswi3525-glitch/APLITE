import UIKit
#if DEBUG
/// Test steps for the Simulator, from the launch argument `-APLiteScript "app:YouTube; wait:8; focus:Settings"`:
/// `app:<name>` opens an installed iOS app, `focus:<title>` raises the window whose title starts with it,
/// `page:apps|settings|files` opens one of APLite's pages, `wait:<seconds>` pauses; also `open:<url>`, `spotlight`,
/// `clipboard`, `audio` / `audio:copy` (session diagnostics), `area`, `shot`, `sticky`, `ontop`, `hot:on`,
/// `type:<text>`, `copy:<text>`, `key:enter|esc|back|up|down`,
/// `snapkey:left|right|up|down`, `move:x,y`, `click:x,y`, `rclick:x,y`, `press:x,y`, `release`, `max`, `scroll:<dy>`. Each step is logged with "[APLite-script]".
enum DebugScript {
    private static var started = false

    static func runIfRequested(_ model: DesktopModel) {
        let args = ProcessInfo.processInfo.arguments
        guard !started, let i = args.firstIndex(of: "-iDeskScript"), i + 1 < args.count else { return }
        started = true
        let steps = args[i + 1].split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        waitForFullDisplay(steps[...], model, tries: 60)
    }

    /// The Simulator's display may come up at 720×480 and be attached again by the test: start once the desktop is
    /// full size (or after 30 s).
    private static func waitForFullDisplay(_ steps: ArraySlice<String>, _ model: DesktopModel, tries: Int) {
        if model.isExternalConnected && model.screenSize.width >= 1200 || tries == 0 {
            NSLog("[APLite-script] start at %.0f×%.0f", model.screenSize.width, model.screenSize.height)
            run(steps, model, after: 2)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { waitForFullDisplay(steps, model, tries: tries - 1) }
    }

    private static func run(_ steps: ArraySlice<String>, _ model: DesktopModel, after delay: TimeInterval) {
        guard let step = steps.first else { NSLog("[APLite-script] done"); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
            let arg = parts.count > 1 ? parts[1] : ""
            var next: TimeInterval = 0.5
            switch parts[0] {
            case "app":
                if let app = GuestStore.shared.apps.first(where: { $0.name == arg }) { model.openApp(app) }
                else { NSLog("[APLite-script] no app %@", arg) }
            case "focus":
                if let w = model.windows.last(where: { $0.title.hasPrefix(arg) }) { model.focus(w) }
                else { NSLog("[APLite-script] no window %@", arg) }
            case "page":
                if let page = [DesktopPage.apps, .settings, .files, .browser, .history].first(where: { "\($0)" == arg }) { model.openPage(page) }
            case "scroll":
                model.cursor.position = CGPoint(x: model.screenSize.width / 2, y: model.screenSize.height / 2)
                model.scroll(dx: 0, dy: CGFloat(Double(arg) ?? 300))
            case "open": model.openWindow(arg)
            case "spotlight": model.toggleSpotlight()
            case "clipboard": model.toggleClipboard()
            case "area": model.startAreaCapture()
            case "shot": model.takeScreenshot()
            case "sticky": model.newSticky()
            case "ontop": if let w = model.focused { model.toggleKeepOnTop(w) }
            case "hot": model.hotCorners = arg == "on"
            case "type": model.typeText(arg)
            case "copy": ClipboardHistory.shared.copy(arg)
            case "key":
                switch arg {
                case "enter": model.pressEnter()
                case "space": model.typeText(" ")
                case "esc": model.escape()
                case "back": model.backspace()
                case "up": model.sendKey("ArrowUp", 38, false)
                case "down": model.sendKey("ArrowDown", 40, false)
                default: break
                }
            case "snapkey":
                let d: [String: DesktopModel.Direction] = ["left": .left, "right": .right, "up": .up, "down": .down]
                if let dir = d[arg] { model.snapFocused(dir) }
            case "move", "click", "rclick", "press":
                let xy = arg.split(separator: ",").compactMap { Double($0) }
                if xy.count == 2 {
                    let c = model.cursor.position
                    model.moveCursor(dx: CGFloat(xy[0]) - c.x, dy: CGFloat(xy[1]) - c.y)
                }
                if parts[0] == "click" { model.click() }
                if parts[0] == "rclick" { model.rightClick() }
                if parts[0] == "press" { model.mouseDown() }
            case "release": model.mouseUp()
            case "drop":
                // drop:<file in Files>@x,y — drag a file shortcut from the desktop and release it at x,y.
                let parts2 = arg.split(separator: "@").map(String.init)
                let xy = parts2.count > 1 ? parts2[1].split(separator: ",").compactMap { Double($0) } : []
                if xy.count == 2 { model.debugDropFile(parts2[0], at: CGPoint(x: xy[0], y: xy[1])) }
            case "file": model.openFile(arg)
            case "export":      // iDesk + the apps as one IPA (what the signing app gets); logs where it is
                GuestStore.shared.exportForESign(progress: { _ in }, completion: { r in
                    switch r {
                    case .success(let url): NSLog("[APLite-script] exported %@", url.path)
                    case .failure(let e): NSLog("[APLite-script] export failed %@", e.localizedDescription)
                    }
                })
            case "install":     // install:/path/App.ipa (a Simulator copy, scripts/sim-ipa.sh)
                GuestStore.shared.install(ipas: [URL(fileURLWithPath: arg)]) { r in
                    NSLog("[APLite-script] %@", GuestStore.summary(of: r))
                }
            case "bookmark": if let w = model.focused { model.toggleBookmark(w) }
            case "emoji": model.toggleEmoji()
            case "rec": ScreenRecorder.shared.toggle()
            case "update": UpdateChecker.shared.download()
            case "checkupdate": UpdateChecker.shared.check(userAsked: true)
            case "lock": model.lockDesktop(force: true)
            case "unlock": model.isLocked = false
            case "saver": model.showScreenSaver = true
            case "playpause": MediaControl.shared.playPause()
            case "audio":
                // `audio` logs the full report; `audio:copy` also puts it on the clipboard.
                let report = AudioSessionManager.shared.report()
                NSLog("[APLite-audio] %@", report)
                if arg == "copy" {
                    AudioSessionManager.shared.copyReportToPasteboard()
                    model.showToast(String(localized: "Audio diagnostics copied"))
                } else {
                    model.showToast(String(localized: "Audio diagnostics written to the console"))
                }
            case "repl":
                let kv = arg.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { TextReplacements.add(kv[0], kv[1]) }
            case "widget": if let k = WidgetKind(rawValue: arg) { WidgetStore.shared.toggle(k); model.showWidgets = true }
            case "pomo": WidgetStore.shared.startPause()
            case "wall": model.wallpaper = Int(arg) ?? 0
            case "night": NightFilter.mode = NightFilter.Mode(rawValue: Int(arg) ?? 0) ?? .off
            case "shake":
                for i in 0..<10 { model.moveCursor(dx: i % 2 == 0 ? 160 : -160, dy: 0) }
            case "js": model.focused?.webView?.evaluateJavaScript(arg)
            case "dl":
                let first = Downloads.shared.items.first?.id
                switch arg {
                case "panel": model.showDownloads.toggle()
                case "pause": if let first { Downloads.shared.pause(first) }
                case "resume": if let first { Downloads.shared.resume(first) }
                case "cancel": if let first { Downloads.shared.cancel(first) }
                default: break
                }
            case "float": if let w = model.focused { model.toggleFloatingVideo(w) }
            case "present": if let w = model.focused { model.startPresentation(w) }
            case "next": model.presentationStep(1)
            case "laser": let xy = arg.split(separator: ",").compactMap { Double($0) }; model.laser = xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
            case "endpresent": model.endPresentation()
            case "dark": DarkPages.isEnabled = arg == "on"
            case "webapp": if let w = model.focused { model.installWebApp(w) }
            case "reader": if let w = model.focused { model.toggleReader(w) }
            case "translate": if let w = model.focused { model.translatePage(w) }
            case "split": if let w = model.focused { model.splitTab(w) }
            case "newtab": if let w = model.focused, let u = URL(string: arg) { model.newTab(in: w, url: u) }
            case "memwarn": model.memoryIsLow()
            case "max":
                if let w = model.focused { model.toggleMaximize(w) }
            case "wait":
                next = Double(arg) ?? 1
            default:
                NSLog("[APLite-script] unknown step %@", step)
            }
            NSLog("[APLite-script] %@", step)
            run(steps.dropFirst(), model, after: next)
        }
    }
}
#endif
