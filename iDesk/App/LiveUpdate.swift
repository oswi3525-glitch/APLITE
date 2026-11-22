import Foundation
import SwiftUI

/// Server-driven configuration refresh.
///
/// iOS does **not** allow an app to replace its own native executable: any new Swift/ObjC code
/// must be signed and reinstalled. APLite therefore separates two things:
///   - `UpdateChecker` downloads a new signed IPA when a real release exists (still needs signing).
///   - `LiveUpdate` fetches a small JSON manifest and refreshes *data only* — wallpaper palettes,
///     an announcement and a theme accent — with no IPA download and no re-signing.
/// The manifest is plain JSON from this repository; nothing in it is executed as code.
struct LiveManifest: Decodable {
    let version: Int
    let notice: String?
    let wallpapers: [[String]]?
    let accent: String?
}

enum LiveUpdate {
    private static let versionKey = "APLite.live.version"
    private static let noticeKey = "APLite.live.notice"
    private static let wallpaperKey = "APLite.live.wallpapers"
    private static let accentKey = "APLite.live.accent"

    private static var url: URL? {
        URL(string: "https://raw.githubusercontent.com/\(APLite.repository)/main/aplite-live.json")
    }

    static var notice: String? {
        UserDefaults.standard.string(forKey: noticeKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var wallpaperColors: [[Color]]? {
        guard let data = UserDefaults.standard.data(forKey: wallpaperKey),
              let hex = try? JSONDecoder().decode([[String]].self, from: data) else { return nil }
        let colors = hex.map { $0.compactMap { Color(hex: $0) } }.filter { !$0.isEmpty }
        return colors.isEmpty ? nil : colors
    }

    static var accent: Color? {
        guard let hex = UserDefaults.standard.string(forKey: accentKey) else { return nil }
        return Color(hex: hex)
    }

    /// Called at launch. Failures are silent — this is a cosmetic refresh, never a build gate.
    static func check() {
        guard UpdateChecker.shared.automatic, let url else { return }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("APLite", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data, let manifest = try? JSONDecoder().decode(LiveManifest.self, from: data),
                  manifest.version > UserDefaults.standard.integer(forKey: versionKey) else { return }
            DispatchQueue.main.async {
                UserDefaults.standard.set(manifest.version, forKey: versionKey)
                if let notice = manifest.notice { UserDefaults.standard.set(notice, forKey: noticeKey) }
                if let walls = manifest.wallpapers, let data = try? JSONEncoder().encode(walls) {
                    UserDefaults.standard.set(data, forKey: wallpaperKey)
                }
                if let accent = manifest.accent { UserDefaults.standard.set(accent, forKey: accentKey) }
                NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
            }
        }.resume()
    }
}

extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = Int(value, radix: 16) else { return nil }
        self.init(red: Double((number >> 16) & 0xff) / 255,
                  green: Double((number >> 8) & 0xff) / 255,
                  blue: Double(number & 0xff) / 255)
    }
}
