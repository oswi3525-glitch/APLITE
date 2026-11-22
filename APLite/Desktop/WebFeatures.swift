import UIKit
import WebKit
import AVFoundation
import NaturalLanguage

// MARK: - Web apps

/// Websites installed as apps (window menu → Install as app): each opens in its own window without an address bar
/// or tabs, with its icon on the desktop, in the app menu and on the taskbar, like a web app on a Mac.
final class WebApps: ObservableObject {
    static let shared = WebApps()
    @Published private(set) var all: [WebEntry] = []
    private static let key = "iDesk.webApps"
    private var icons: [String: UIImage] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let list = try? JSONDecoder().decode([WebEntry].self, from: data) { all = list }
        // Load the little icon files once here instead of decoding them from SwiftUI's body on
        // the first draw of each dock icon.
        for entry in all { icons[entry.url] = UIImage(contentsOfFile: Self.iconURL(entry.url).path) }
    }

    private static var iconFolder: URL {
        let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("WebApps", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func iconURL(_ url: String) -> URL {
        let name = String(url.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }, radix: 16)
        return iconFolder.appendingPathComponent(name + ".png")
    }

    func isInstalled(_ url: String) -> Bool { all.contains { Browsing.same($0.url, url) } }

    func install(_ url: URL, title: String, icon: UIImage?) {
        let key = url.absoluteString
        guard Browsing.isWebPage(url), !isInstalled(key) else { return }
        if let icon, let png = icon.pngData() {
            try? png.write(to: Self.iconURL(key))
            icons[key] = icon
        }
        let name = title.isEmpty ? (url.host ?? key) : title
        all.append(WebEntry(url: key, title: name, date: Date()))
        save()
    }

    func remove(_ url: String) {
        all.removeAll { Browsing.same($0.url, url) }
        try? FileManager.default.removeItem(at: Self.iconURL(url))
        icons[url] = nil
        save()
    }

    func icon(for url: String) -> UIImage? {
        if let cached = icons[url] { return cached }
        let image = UIImage(contentsOfFile: Self.iconURL(url).path)
        // Bound the in-memory cache; a user who installs hundreds of sites should not keep every
        // decoded icon alive. The PNG stays on disk and is reloaded if needed again.
        if icons.count >= 64 { icons.removeAll() }
        icons[url] = image
        return image
    }

    private func save() {
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

// MARK: - Dark pages

/// Settings → Browser → Dark pages: light web pages are shown dark (colours turned around, pictures and videos
/// kept as they are). Pages that are dark already, or say they handle dark mode, are left alone.
enum DarkPages {
    private static let key = "iDesk.darkPages"
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            for w in DesktopModel.shared.windows {
                for tab in w.tabs { tab.evaluateJavaScript("window.__ideskDark && __ideskDark(\(newValue))") }
            }
        }
    }

    /// Added to every tab; `on` is the setting when the tab is made, `__ideskDark(on)` changes it later.
    static func script() -> WKUserScript {
        let source = """
        (() => {
          if (location.protocol === 'idesk:' || location.protocol === 'file:') return;
          let on = \(isEnabled);
          const css = 'html.idesk-dark{filter:invert(0.9) hue-rotate(180deg)!important;background:#fff!important}'
            + 'html.idesk-dark img,html.idesk-dark video,html.idesk-dark picture,html.idesk-dark canvas,'
            + 'html.idesk-dark iframe,html.idesk-dark [style*="background-image"]{filter:invert(1) hue-rotate(180deg)!important}';
          function isLight() {
            const meta = document.querySelector('meta[name="color-scheme"]');
            if (meta && /dark/.test(meta.content)) return false;
            for (const el of [document.body, document.documentElement]) {
              if (!el) continue;
              const m = getComputedStyle(el).backgroundColor.match(/[\\d.]+/g);
              if (!m) continue;
              const [r, g, b, a] = m.map(Number);
              if (m.length > 3 && a === 0) continue;
              return (0.299 * r + 0.587 * g + 0.114 * b) > 150;
            }
            return true;
          }
          function apply() {
            if (!document.getElementById('idesk-dark-css')) {
              const st = document.createElement('style'); st.id = 'idesk-dark-css'; st.textContent = css;
              (document.head || document.documentElement).appendChild(st);
            }
            const root = document.documentElement;
            root.classList.remove('idesk-dark');
            if (on && isLight()) root.classList.add('idesk-dark');
          }
          window.__ideskDark = v => { on = v; apply(); };
          if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', apply); else apply();
          window.addEventListener('load', apply);
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }
}

// MARK: - Reader view and reading aloud

enum Reader {
    /// Replaces the page with its article only (title, text, pictures) in a calm layout; "Close reader" reloads it.
    static let script = """
    (() => {
      if (window.__ideskReader) { location.reload(); return 'closed'; }
      const candidates = Array.from(document.querySelectorAll('article, main, [role="main"], .post, .article, .content, #content, body'));
      let best = document.body, score = 0;
      for (const el of candidates) {
        const text = Array.from(el.querySelectorAll('p')).reduce((n, p) => n + p.innerText.length, 0);
        if (text > score * 1.2) { best = el; score = text; }
      }
      const parts = [];
      for (const n of best.querySelectorAll('h1, h2, h3, p, img, blockquote, li, pre, figure figcaption')) {
        if (n.closest('nav, footer, aside, form')) continue;
        if (n.tagName === 'IMG') { if (n.naturalWidth > 200 || n.width > 200) parts.push('<img src="' + n.currentSrc + '">'); continue; }
        const t = n.innerText.trim();
        if (t.length < 2) continue;
        const tag = n.tagName === 'FIGCAPTION' ? 'p' : n.tagName.toLowerCase();
        const esc = t.replace(/&/g, '&amp;').replace(/</g, '&lt;');
        parts.push('<' + tag + '>' + esc + '</' + tag + '>');
      }
      const title = document.title.replace(/&/g, '&amp;').replace(/</g, '&lt;');
      document.documentElement.innerHTML = '<head><meta name="color-scheme" content="dark light"><title>' + title + '</title><style>'
        + 'body{max-width:720px;margin:40px auto;padding:0 24px 80px;font:20px/1.65 -apple-system,Georgia,serif;background:#1c1c1e;color:#e5e5ea}'
        + 'h1{font-size:34px;line-height:1.2}h1,h2,h3{font-family:-apple-system}img{max-width:100%;border-radius:10px;margin:12px 0}'
        + 'blockquote{border-left:3px solid #636366;margin:0;padding-left:16px;color:#aeaeb2}pre{white-space:pre-wrap}'
        + '#idesk-close{position:fixed;top:16px;right:16px;font:600 14px -apple-system;padding:8px 14px;border-radius:999px;border:0;background:#3a3a3c;color:#fff}'
        + '</style></head><body><button id="idesk-close" onclick="location.reload()">×</button><h1>' + title + '</h1>' + parts.join('') + '</body>';
      window.__ideskReader = true;
      scrollTo(0, 0);
      return 'opened';
    })()
    """

    /// The article's text, for reading aloud.
    static let textScript = """
    (() => {
      const root = document.querySelector('article, main, [role="main"]') || document.body;
      return Array.from(root.querySelectorAll('h1, h2, h3, p, li')).map(n => n.innerText.trim()).filter(t => t.length > 1).join('\\n');
    })()
    """
}

/// Reads text aloud with the iPhone's voices, in the language the text is written in.
final class ReadAloud: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    static let shared = ReadAloud()
    private let synth = AVSpeechSynthesizer()
    private(set) var isSpeaking = false

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) {
        stop()
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2000)))
        let language = recognizer.dominantLanguage?.rawValue ?? Locale.current.language.languageCode?.identifier ?? "en"
        // Reuse the shared playback session. Setting a category here without ever activating it (the
        // old behaviour) left speech silent whenever another component had deactivated the session.
        AudioSessionManager.shared.activatePlayback(reason: "read aloud")
        for paragraph in text.components(separatedBy: "\n") where !paragraph.trimmingCharacters(in: .whitespaces).isEmpty {
            let u = AVSpeechUtterance(string: paragraph)
            u.voice = AVSpeechSynthesisVoice(language: language)
            u.postUtteranceDelay = 0.15
            synth.speak(u)
        }
        isSpeaking = true
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if !synthesizer.isSpeaking { isSpeaking = false }
    }
}

// MARK: - Translation

enum Translate {
    /// The page through Google Translate, into the iPhone's language (Vietnamese on a Vietnamese iPhone).
    static func url(for page: URL) -> URL? {
        guard Browsing.isWebPage(page) else { return nil }
        let target = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "vi"
        var c = URLComponents(string: "https://translate.google.com/translate")!
        c.queryItems = [URLQueryItem(name: "sl", value: "auto"), URLQueryItem(name: "tl", value: target),
                        URLQueryItem(name: "u", value: page.absoluteString)]
        return c.url
    }
}

// MARK: - Desktop actions

extension DesktopModel {
    func installWebApp(_ w: DeskWindow) {
        let url = w.currentURL
        guard Browsing.isWebPage(url) else { return }
        WebApps.shared.install(url, title: w.title, icon: w.favicon)
        objectWillChange.send()
        showToast(String(localized: "“\(w.title)” is now an app on the desktop and in the app menu"))
    }

    /// Opens a web app in its own window (or brings its window to the front).
    func openWebApp(_ url: String) {
        guard let target = URL(string: url) else { return }
        if let w = windows.first(where: { $0.isWebApp && $0.initialURL == target }) { focus(w); return }
        openWindow(target, webApp: true)
    }

    /// The tab shown moves to its own window beside this one: this window takes the left half, the new one the right.
    func splitTab(_ w: DeskWindow) {
        guard w.isBrowser, w.tabs.count > 1 else { return }
        let url = w.url(ofTab: w.activeTab)
        closeTab(w.activeTab, of: w)
        snapWindow(w, .left)
        openWindow(url)
        if let new = windows.last, new !== w { snapWindow(new, .right) }
    }

    func translatePage(_ w: DeskWindow) {
        guard let url = Translate.url(for: w.currentURL) else { return }
        w.load(url)
    }

    func toggleReader(_ w: DeskWindow) {
        w.webView?.evaluateJavaScript(Reader.script)
    }

    func readAloud(_ w: DeskWindow) {
        if ReadAloud.shared.isSpeaking { ReadAloud.shared.stop(); return }
        w.webView?.evaluateJavaScript(Reader.textScript) { [weak self] result, _ in
            guard let text = result as? String, !text.isEmpty else {
                self?.showToast(String(localized: "No text to read on this page")); return
            }
            ReadAloud.shared.speak(text)
        }
    }
}
