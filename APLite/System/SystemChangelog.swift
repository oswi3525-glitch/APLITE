import SwiftUI

/// In-app record of what actually changed in each build. The full history stays in CHANGELOG.md;
/// this is the short version shown on the device so updates are never silent.
enum SystemChangelog {
    struct Entry: Identifiable {
        let version: String
        let date: String
        let items: [String]
        var id: String { version }
    }

    static let entries: [Entry] = [
        Entry(version: "1.3.0 (beta 3)", date: "2026-11-24", items: [
            "Icon and wallpaper assets now compile correctly — the branded icons and bundled wallpapers are visible again.",
            "Zalo Web opens properly and YouTube ads can be skipped from within APLite's browser.",
            "Certificate import explains the real error; saved signing identities are no longer lost on upgrade.",
            "The dock is centered, and 'Add IPA app to desktop…' puts a guest app icon on the desktop that opens as a window.",
        ]),
        Entry(version: "1.3.0 (beta 2)", date: "2026-11-24", items: [
            "Security: crash reports are redacted before they can be shared in a public issue; saved logins, logs and survey exports use iOS Data Protection.",
            "Beta survey now opens on the iPhone screen — the external display cannot receive drag gestures. A four-finger hold no longer interrupts a swipe.",
            "Auto-lock after now actually locks the desktop when idle. Cleanup scanning and log reading no longer block the main thread.",
            "Release builds show 1.3.0 (beta 2) correctly; a normal build from this source is stable and hides all beta-only features.",
        ]),
        Entry(version: "1.3.0 (beta 1)", date: "2026-11-24", items: [
            "Boot: the startup watchdog now runs off the main thread and every boot phase is timed in the System Log. A legacy cache flag no longer blocks launch and preview mode no longer stays on the boot screen.",
            "System Log: Settings → Privacy & Security → System Log shows timestamped events by level and can be filtered or cleared. It is APLite's own log, not the iOS system log.",
            "Settings is now five tabs: System, Apps, Privacy & Security, Cleanup & Optimize and APStore. All previous controls live in the System tab unchanged.",
            "APStore lists Web Apps and signed Native Modules separately and checks module integrity. iOS does not allow installing arbitrary external IPAs.",
            "Cleanup removes only APLite-owned caches, stale temporary files and old reports. No feature scans or cleans other apps.",
            "Beta survey: hold four fingers, drag over the problem area, add a note, then export one JSON file. A single four-finger tap still opens the app menu. This feature is hidden on stable builds.",
        ]),
        Entry(version: "1.2.9", date: "2026-11-23", items: [
            "Desktop keyboard: drag its title bar to move it, −/× in the corner to collapse or close, and Reset keyboard position in Settings → Input.",
            "New Window button on the dock: a compact list of open windows; click to focus/restore, × to close, plus Tile and Show desktop.",
            "Thermal readout: a 0–100% pressure index with trend, time in state and session peak in the tray, quick panel and diagnostics. iOS has no public °C API — this is an index, not a temperature sensor.",
            "Settings trimmed: Build Center/App Creator, certificates and diagnostics now live on one Advanced page; the no-op idle-cache toggle is gone.",
        ]),
        Entry(version: "1.2.8", date: "2026-11-23", items: [
            "Audio: popup web views now inherit media settings and bridges; guest audio is no longer cut by the idle timer; category changes and voice-typing interruptions recover correctly.",
            "New Technical Diagnostics page, reachable only from Settings → System — no desktop icon, dock item or launcher entry.",
            "Settings: clearer grouped sections with icons, optional Light appearance on iPhone, and confirmation for destructive actions.",
            "Windows: one consistent chrome style, animated fullscreen/maximize, zoom buttons with the current level in WebApp title bars.",
            "Trash: bundled guest apps are marked honestly for reinstall, the Trash icon is protected, and the last removed WebApp can be restored.",
        ]),
        Entry(version: "1.2.7", date: "2026-11-23", items: [
            "Browser: real, versioned Safari identity for desktop WKWebView — fixes Gmail's unsupported-browser banner without faking an engine.",
            "Shared WebContent process pool, automatic reload after a WebContent crash, and safer sign-in popup handling.",
            "Colors: one sRGB palette — a declared #FF0000 stays red instead of turning pink; danger colors and the remote accent are normalised.",
            "Drag apps to the Trash: WebApps uninstall, guest apps respect code-signing limits, system items are protected.",
            "WebApp zoom: 9 unified levels, official WKWebView.pageZoom, saved separately for each WebApp, with a 100% reset.",
            "Removed the last user-visible iDesk wording; attribution and all compatibility identifiers are preserved.",
        ]),
        Entry(version: "1.2.6", date: "2026-11-23", items: [
            "Logins in any web window — including on the external display — are saved to the local account vault automatically.",
            "On-screen keyboard for the desktop: enable it in Settings, tap a field to show it, use × or Esc to hide it.",
            "Full keyboard settings page with every key, Shift / Caps Lock / 123 layers, sizing and click feedback.",
            "Tabs: find bar no longer leaks between tabs, closed tabs reopen in place, and web apps keep their branded icon and name.",
            "Clean Facebook layout (togglable in Browser settings) and a more readable tab strip with site icons.",
        ]),
        Entry(version: "1.2.5", date: "2026-11-22", items: [
            "Analogue clock on the desktop widget, lock screen, screen saver and quick panel.",
            "New 'Biển' ocean wallpaper next to 'Đồng cỏ'; both shown as real thumbnails in Settings.",
            "Zalo, Facebook, Telegram, Chrome, YouTube and Gmail get branded icons and install on first launch.",
            "Widgets tick at their own cadence — less idle redrawing, less heat.",
            "Source folder renamed iDesk → APLite; settings and guest apps are preserved.",
        ]),
        Entry(version: "1.2.4", date: "2026-11-22", items: [
            "Audio session is released when the desktop is silent — less heat and battery drain.",
            "WebKit / URL caches trimmed every 5 minutes; memory stays flatter in long sessions.",
            "Instant animations automatically when iOS reports the device is warm.",
            "One-tap web apps: Chrome, Zalo, Facebook, Telegram (web shortcuts, not native apps).",
        ]),
        Entry(version: "1.2.3", date: "2026-11-22", items: [
            "Raised the dock icons and enlarged the floating pills.",
            "Saved the signed-in Google account into APLite's local cookie vault.",
            "Reduced idle work: tray redraw 5s → 15s, memory sampling 5s → 10s.",
            "App Creator: Python and Node.js templates, a read-only project preview.",
            "New hand-drawn 'Đồng cỏ' meadow wallpaper plus a matching gradient.",
            "Added resolution control to native System settings.",
            "More audio fixes: always recover after interruptions and route changes.",
        ]),
        Entry(version: "1.2.2", date: "2026-11-22", items: [
            "Desktop Settings → About can open native System settings / Build Center.",
        ]),
        Entry(version: "1.2.1", date: "2026-11-22", items: [
            "Audio recovery no longer depends on shouldResume.",
            "Voice typing rolls back the session when the engine fails.",
            "Web Audio contexts resume with __ideskVolumeResume.",
            "Build Center can generate real XcodeGen app projects.",
        ]),
        Entry(version: "1.2.0", date: "2026-11-22", items: [
            "Independent System modules: Security, Power, Memory, Certificates, Files, Windows, Build Center.",
            "Passcode in Keychain with brute-force backoff; software Sleep/Wake/Shutdown.",
            "1 GB memory target, peak display, leak hints and cache release.",
            "P12/PFX typed import errors; APLite managed file area.",
        ]),
    ]
}

struct SystemChangelogView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(SystemChangelog.entries) { entry in
                    Section("\(entry.version) · \(entry.date)") {
                        ForEach(entry.items, id: \.self) { Text("• \($0)").font(.footnote) }
                    }
                }
            }
            .navigationTitle("What's new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
