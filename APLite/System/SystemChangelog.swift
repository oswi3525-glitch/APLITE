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
        .preferredColorScheme(.dark)
    }
}
