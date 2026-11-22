import UIKit

/// Which iOS apps are known to work inside iDesk, from compat.json in the GitHub repository (so the list grows without
/// a new iDesk), with the copy below when GitHub can't be reached. People report how an app ran with a ready-made
/// GitHub issue.
final class Compatibility: ObservableObject {
    static let shared = Compatibility()

    struct Entry: Codable, Equatable {
        let id: String
        let name: String
        let status: String          // works · partial · broken
        let vi: String
        let en: String
        var note: String { Locale.preferredLanguages.first?.hasPrefix("vi") == true ? vi : en }
    }
    private struct List: Codable { let apps: [Entry] }

    @Published private(set) var entries: [Entry] = Compatibility.cached ?? Compatibility.builtIn

    private static let url = URL(string: "https://raw.githubusercontent.com/\(APLite.repository)/main/compat.json")!
    private static let cacheKey = "iDesk.compatList"
    private var fetched = false

    func entry(for id: String) -> Entry? { entries.first { $0.id == id } }

    /// Fetches the latest list once per launch.
    func refresh() {
        guard !fetched else { return }
        fetched = true
        var request = URLRequest(url: Self.url, timeoutInterval: 15)
        request.setValue("APLite", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data, let list = try? JSONDecoder().decode(List.self, from: data), !list.apps.isEmpty else { return }
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
            DispatchQueue.main.async { self.entries = list.apps }
        }.resume()
    }

    /// A GitHub issue, filled in with the app, its version, the iPhone and iDesk, for the user to say how it ran.
    static func reportURL(for app: GuestApp) -> URL? {
        let info = NSDictionary(contentsOf: app.bundleURL.appendingPathComponent("Info.plist"))
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        var model = utsname(); uname(&model)
        let machine = withUnsafeBytes(of: &model.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let body = """
        **App:** \(app.name) \(version) (\(app.id))
        **APLite:** \(UpdateChecker.current)
        **iPhone / iPad:** \(machine), iOS \(UIDevice.current.systemVersion)
        **Bản gốc hay bản mod / Original or modded:**

        **Chạy thế nào? / How did it run?** (mở được, đăng nhập, phát video, văng… / opens, signs in, plays video, crashes…)

        """
        var c = URLComponents(string: "https://github.com/\(APLite.repository)/issues/new")!
        c.queryItems = [URLQueryItem(name: "title", value: "[App] \(app.name) \(version)"),
                        URLQueryItem(name: "labels", value: "app-report"),
                        URLQueryItem(name: "body", value: body)]
        return c.url
    }

    private static var cached: [Entry]? {
        UserDefaults.standard.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(List.self, from: $0).apps }
    }

    private static let builtIn: [Entry] = [
        Entry(id: "com.google.ios.youtube", name: "YouTube", status: "partial",
              vi: "Bản gốc có thể không phát được video.",
              en: "The original app may not play video."),
        Entry(id: "com.facebook.Facebook", name: "Facebook", status: "partial",
              vi: "Có thể bị hỏi captcha khi đăng nhập.",
              en: "May ask for a captcha at sign-in."),
        Entry(id: "com.zhiliaoapp.musically", name: "TikTok", status: "works",
              vi: "Chạy tốt.",
              en: "Works."),
    ]
}
