import SwiftUI

/// Spotlight (⌘ + Space, or the magnifier on the taskbar): one field that finds open windows, apps and web
/// shortcuts, files, bookmarks and history, works out sums ("12*3+4") and converts units ("5 km to mi"), and
/// otherwise searches the web. ↑ ↓ pick a result, Enter opens it, Esc closes.
struct SpotlightResult {
    enum Kind { case answer, window, app, recent, file, bookmark, history, web }
    let kind: Kind
    let title: String
    var subtitle: String = ""
    var symbol: String = "magnifyingglass"
    var shortcut: Shortcut? = nil
    var image: UIImage? = nil
    let action: () -> Void

    var label: LocalizedStringKey {
        switch kind {
        case .answer: return "Answer"
        case .window: return "Open window"
        case .app: return "App"
        case .recent: return "Recent"
        case .file: return "File"
        case .bookmark: return "Bookmark"
        case .history: return "History"
        case .web: return "Web"
        }
    }
}

enum Spotlight {
    static let width: CGFloat = 660
    static let field: CGFloat = 58
    static let row: CGFloat = 46
    static let padding: CGFloat = 8
    static let maxRows = 9

    /// Every file in Files (paths inside it), read when Spotlight opens.
    static func indexFiles() -> [String] {
        let root = FileStore.downloads
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var paths: [String] = []
        for case let url as URL in e {
            if let p = FileStore.relativePath(of: url) { paths.append(p) }
            if paths.count >= 4000 { break }
        }
        return paths
    }

    /// How well `text` matches `query`: 3 starts with it, 2 a word starts with it, 1 contains it, 0 no match.
    static func score(_ text: String, _ query: String) -> Int {
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        guard let r = text.range(of: query, options: opts) else { return 0 }
        if r.lowerBound == text.startIndex { return 3 }
        let before = text[text.index(before: r.lowerBound)]
        return before.isLetter || before.isNumber ? 1 : 2
    }
}

extension DesktopModel {
    func toggleSpotlight() {
        guard isExternalConnected else { return }
        let open = !showSpotlight
        closePanels()
        showSpotlight = open
    }

    var spotlightResults: [SpotlightResult] {
        if let cached = spotlightCache { return cached }
        let results = computeSpotlightResults()
        spotlightCache = results
        return results
    }

    private func computeSpotlightResults() -> [SpotlightResult] {
        let q = spotlightQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            // Nothing typed: what was opened last.
            return launcherRecents.prefix(6).map { item in
                SpotlightResult(kind: .recent, title: item.name, subtitle: "",
                                symbol: item.symbol, shortcut: item) { [weak self] in self?.open(item) }
            }
        }
        var out: [SpotlightResult] = []

        // A sum or a unit conversion: the answer first; Enter copies it.
        if let answer = Calculator.answer(for: q) {
            out.append(SpotlightResult(kind: .answer, title: answer.text, subtitle: answer.detail,
                                       symbol: answer.isUnit ? "ruler" : "equal.square") { [weak self] in
                ClipboardHistory.shared.copy(answer.value)
                self?.showToast(String(localized: "Copied “\(answer.value)”"))
            })
        }

        // Open windows (focusing one also brings it back from minimized or another workspace).
        let wins = windows.reversed().map { ($0, Spotlight.score($0.title, q)) }.filter { $0.1 > 0 }
        for (w, _) in wins.sorted(by: { $0.1 > $1.1 }).prefix(3) {
            out.append(SpotlightResult(kind: .window, title: w.title,
                                       subtitle: w.guestApp?.name ?? w.currentURL.host ?? "",
                                       symbol: w.symbol, image: w.icon) { [weak self] in self?.focus(w) })
        }

        // Apps, web shortcuts and APLite's pages.
        let apps = items.map { ($0, Spotlight.score($0.name, q)) }.filter { $0.1 > 0 }
        for (item, _) in apps.sorted(by: { $0.1 > $1.1 }).prefix(4) {
            out.append(SpotlightResult(kind: .app, title: item.name,
                                       subtitle: item.app?.id ?? item.file ?? URL(string: item.url)?.host ?? "",
                                       symbol: item.symbol, shortcut: item) { [weak self] in self?.open(item) })
        }

        // Files, by name.
        let files = spotlightFiles.map { ($0, Spotlight.score(($0 as NSString).lastPathComponent, q)) }.filter { $0.1 > 0 }
        for (path, _) in files.sorted(by: { $0.1 > $1.1 }).prefix(3) {
            let name = (path as NSString).lastPathComponent
            let isFolder = FileStore.resolve(path).map(FileStore.isFolder) ?? false
            let parent = (path as NSString).deletingLastPathComponent
            out.append(SpotlightResult(kind: .file, title: name,
                                       subtitle: parent.isEmpty ? String(localized: "Files") : String(localized: "Files") + " › " + parent,
                                       symbol: isFolder ? "folder.fill" : FileStore.iconSymbol(for: (name as NSString).pathExtension)) { [weak self] in
                self?.openFile(path)
            })
        }

        // Bookmarks, then pages from the history (each address once).
        var seen = Set<String>()
        let browsing = Browsing.shared
        for (entries, kind, limit) in [(browsing.bookmarks, SpotlightResult.Kind.bookmark, 3), (browsing.history, .history, 3)] {
            var n = 0
            for e in entries where n < limit && !seen.contains(e.url) {
                guard max(Spotlight.score(e.title, q), Spotlight.score(e.url, q)) > 0, let url = URL(string: e.url) else { continue }
                seen.insert(e.url)
                n += 1
                out.append(SpotlightResult(kind: kind, title: e.title.isEmpty ? e.url : e.title, subtitle: url.host ?? e.url,
                                           symbol: kind == .bookmark ? "star.fill" : "clock") { [weak self] in
                    self?.openWindow(url)
                })
            }
        }

        // Last: the web (or the address typed).
        let target = Self.url(from: q)
        let isAddress = target.host != "www.google.com"
        out.append(SpotlightResult(kind: .web,
                                   title: isAddress ? String(localized: "Open \(q)") : String(localized: "Search the web for “\(q)”"),
                                   subtitle: isAddress ? target.absoluteString : "Google",
                                   symbol: isAddress ? "safari" : "globe") { [weak self] in self?.openWindow(target) })
        return Array(out.prefix(Spotlight.maxRows))
    }

    var spotlightRect: CGRect {
        let rows = CGFloat(spotlightResults.count)
        let hint: CGFloat = spotlightQuery.isEmpty ? 34 : 0
        let h = Spotlight.padding * 2 + Spotlight.field + (rows > 0 ? 6 + rows * Spotlight.row : 0) + hint
        let w = min(Spotlight.width, screenSize.width - 40)
        return CGRect(x: (screenSize.width - w) / 2, y: max(16, screenSize.height * 0.16), width: w, height: h)
    }

    func spotlightRowRect(_ i: Int) -> CGRect {
        let r = spotlightRect
        return CGRect(x: r.minX + Spotlight.padding, y: r.minY + Spotlight.padding + Spotlight.field + 6 + CGFloat(i) * Spotlight.row,
                      width: r.width - Spotlight.padding * 2, height: Spotlight.row)
    }

    func moveSpotlightSelection(_ delta: Int) {
        let n = spotlightResults.count
        guard n > 0 else { return }
        spotlightIndex = (spotlightIndex + delta + n) % n
    }

    func commitSpotlight(_ index: Int? = nil) {
        let results = spotlightResults
        let i = index ?? spotlightIndex
        guard results.indices.contains(i) else { return }
        showSpotlight = false
        results[i].action()
    }

    /// A click while Spotlight is open: on a result opens it; anywhere else outside closes Spotlight.
    func clickSpotlight(at p: CGPoint) {
        if let i = spotlightResults.indices.first(where: { spotlightRowRect($0).contains(p) }) { commitSpotlight(i); return }
        if !spotlightRect.contains(p) { showSpotlight = false }
    }
}

// MARK: - Sums and units

/// Works out what is typed in Spotlight: arithmetic ("(12+3)*4", "2^10", "15% of 80") and unit conversions
/// ("5 km to mi", "100 f in c", "2 GB to MB"). Its own small parser: NSExpression raises an exception (which
/// would close APLite) on many inputs.
enum Calculator {
    struct Answer {
        let text: String      // shown: "= 52"
        let value: String     // copied: "52"
        let detail: String    // "(12+3)*4"
        let isUnit: Bool
    }

    static func answer(for query: String) -> Answer? {
        if let a = convert(query) { return a }
        var s = query.lowercased().replacingOccurrences(of: " ", with: "")
        if s.hasPrefix("=") { s.removeFirst() }
        // "15% of 80" / "15%x80" → 0.15*80
        s = s.replacingOccurrences(of: "%of", with: "%*")
        guard s.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/x×÷^%()")) != nil,
              s.rangeOfCharacter(from: .decimalDigits) != nil,
              s.allSatisfy({ "0123456789.,+-*/x×÷^%()".contains($0) }) else { return nil }
        var p = Parser(Array(s))
        guard let v = p.expression(), p.atEnd, v.isFinite else { return nil }
        let text = format(v)
        return Answer(text: "= " + text, value: text, detail: query.trimmingCharacters(in: .whitespaces), isUnit: false)
    }

    static func format(_ v: Double, digits: Int? = nil) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = digits ?? (abs(v) < 1 ? 8 : 6)
        f.usesGroupingSeparator = abs(v) >= 10000
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    /// Recursive descent: expression = term (± term)*; term = power (×÷ power)*; power = unary (^ power)?;
    /// unary = -unary | number %? | ( expression ).
    private struct Parser {
        let c: [Character]
        var i = 0
        init(_ c: [Character]) { self.c = c }
        var atEnd: Bool { i == c.count }

        mutating func expression() -> Double? {
            guard var v = term() else { return nil }
            while i < c.count, c[i] == "+" || c[i] == "-" {
                let op = c[i]; i += 1
                guard let r = term() else { return nil }
                v = op == "+" ? v + r : v - r
            }
            return v
        }
        mutating func term() -> Double? {
            guard var v = power() else { return nil }
            while i < c.count, "*/x×÷".contains(c[i]) {
                let op = c[i]; i += 1
                guard let r = power() else { return nil }
                if op == "/" || op == "÷" { guard r != 0 else { return nil }; v /= r } else { v *= r }
            }
            return v
        }
        mutating func power() -> Double? {
            guard let b = unary() else { return nil }
            if i < c.count, c[i] == "^" {
                i += 1
                guard let e = power() else { return nil }
                return pow(b, e)
            }
            return b
        }
        mutating func unary() -> Double? {
            guard i < c.count else { return nil }
            if c[i] == "-" { i += 1; return unary().map { -$0 } }
            if c[i] == "+" { i += 1; return unary() }
            var v: Double
            if c[i] == "(" {
                i += 1
                guard let e = expression(), i < c.count, c[i] == ")" else { return nil }
                i += 1
                v = e
            } else {
                let start = i
                while i < c.count, c[i].isNumber || c[i] == "." || c[i] == "," { i += 1 }
                guard i > start else { return nil }
                // "1,5" and "1.5" are both one and a half; "1,000" (three digits after) is a thousand.
                var digits = String(c[start..<i])
                if let comma = digits.firstIndex(of: ",") {
                    let after = digits[digits.index(after: comma)...]
                    digits = after.count == 3 && !digits.contains(".") ? digits.replacingOccurrences(of: ",", with: "")
                                                                       : digits.replacingOccurrences(of: ",", with: ".")
                }
                guard let n = Double(digits) else { return nil }
                v = n
            }
            if i < c.count, c[i] == "%" { i += 1; v /= 100 }
            return v
        }
    }

    // Units: name → (dimension, factor to the base unit). Temperatures are handled apart.
    private static let units: [String: (String, Double)] = {
        var u: [String: (String, Double)] = [:]
        func add(_ dim: String, _ f: Double, _ names: String...) { for n in names { u[n] = (dim, f) } }
        add("length", 0.001, "mm"); add("length", 0.01, "cm"); add("length", 1, "m", "meter", "meters", "mét")
        add("length", 1000, "km"); add("length", 0.0254, "in", "inch", "inches"); add("length", 0.3048, "ft", "foot", "feet")
        add("length", 0.9144, "yd", "yard", "yards"); add("length", 1609.344, "mi", "mile", "miles", "dặm")
        add("mass", 0.001, "g", "gram", "grams"); add("mass", 1, "kg"); add("mass", 1000, "t", "ton", "tấn")
        add("mass", 0.45359237, "lb", "lbs", "pound", "pounds"); add("mass", 0.028349523125, "oz", "ounce", "ounces")
        add("volume", 0.001, "ml"); add("volume", 1, "l", "liter", "liters", "lít"); add("volume", 3.785411784, "gal", "gallon", "gallons")
        add("volume", 0.0295735295625, "floz"); add("volume", 0.2365882365, "cup", "cups")
        add("speed", 1 / 3.6, "kmh", "km/h", "kph"); add("speed", 0.44704, "mph"); add("speed", 1, "m/s", "mps"); add("speed", 0.514444, "knot", "knots", "kn")
        add("area", 1, "m2", "m²"); add("area", 1_000_000, "km2", "km²"); add("area", 10_000, "ha", "hectare", "hécta")
        add("area", 0.09290304, "ft2", "ft²", "sqft"); add("area", 4046.8564224, "acre", "acres")
        add("data", 1, "b", "byte", "bytes"); add("data", 1e3, "kb"); add("data", 1e6, "mb"); add("data", 1e9, "gb"); add("data", 1e12, "tb")
        add("time", 1, "s", "sec", "second", "seconds", "giây"); add("time", 60, "min", "minute", "minutes", "phút")
        add("time", 3600, "h", "hr", "hour", "hours", "giờ"); add("time", 86400, "day", "days", "ngày"); add("time", 604800, "week", "weeks", "tuần")
        return u
    }()

    private static func temperature(_ name: String) -> String? {
        switch name { case "c", "°c", "celsius": return "C"; case "f", "°f", "fahrenheit": return "F"; case "k", "kelvin": return "K"
        default: return nil }
    }

    static func convert(_ query: String) -> Answer? {
        let pattern = #"^\s*(-?[\d.,]+)\s*([^\s\d]+(?:/[a-z]+)?)\s+(?:to|in|sang|ra|=)\s+([^\s\d]+(?:/[a-z]+)?)\s*$"#
        guard let m = query.lowercased().range(of: pattern, options: .regularExpression) else { return nil }
        let s = String(query.lowercased()[m])
        guard let re = try? NSRegularExpression(pattern: pattern),
              let r = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), r.numberOfRanges == 4,
              let a = Range(r.range(at: 1), in: s), let b = Range(r.range(at: 2), in: s), let c = Range(r.range(at: 3), in: s),
              let n = Double(s[a].replacingOccurrences(of: ",", with: ".")) else { return nil }
        let from = String(s[b]), to = String(s[c])
        var v: Double
        var unit = to
        if let tf = temperature(from), let tt = temperature(to) {
            unit = tt == "K" ? "K" : "°" + tt
            let celsius = tf == "C" ? n : tf == "F" ? (n - 32) * 5 / 9 : n - 273.15
            v = tt == "C" ? celsius : tt == "F" ? celsius * 9 / 5 + 32 : celsius + 273.15
        } else if let uf = units[from], let ut = units[to], uf.0 == ut.0 {
            v = n * uf.1 / ut.1
        } else {
            return nil
        }
        if abs(v) < 1e-12 { v = 0 }
        let text = format(v, digits: abs(v) < 1 ? 6 : 4)
        return Answer(text: "= " + text + " " + unit, value: text, detail: query.trimmingCharacters(in: .whitespaces), isUnit: true)
    }
}

// MARK: - View

struct SpotlightView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var cursor: CursorModel

    var body: some View {
        let r = model.spotlightRect
        let results = model.spotlightResults
        ZStack(alignment: .topLeading) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 22, weight: .medium)).foregroundStyle(.secondary)
                Group {
                    if model.spotlightQuery.isEmpty {
                        Text("Spotlight Search").foregroundStyle(.secondary)
                    } else {
                        Text(verbatim: model.spotlightQuery) + Text(verbatim: "|").foregroundColor(.accentColor)
                    }
                }
                .font(.system(size: 24, weight: .regular))
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(width: r.width - Spotlight.padding * 2, height: Spotlight.field)
            .offset(x: Spotlight.padding, y: Spotlight.padding)

            if !results.isEmpty {
                Rectangle().fill(Color.white.opacity(0.1)).frame(width: r.width, height: 1)
                    .offset(y: Spotlight.padding + Spotlight.field + 2)
            }
            ForEach(Array(results.enumerated()), id: \.offset) { i, res in
                let t = model.spotlightRowRect(i)
                let selected = i == model.spotlightIndex
                let hovered = t.contains(cursor.position)
                HStack(spacing: 12) {
                    icon(res).frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: res.title).font(.system(size: 15, weight: res.kind == .answer ? .semibold : .regular)).lineLimit(1)
                        if !res.subtitle.isEmpty {
                            Text(verbatim: res.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(res.label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    if selected { Text(verbatim: "↵").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 10)
                .frame(width: t.width, height: t.height)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.55) : hovered ? Color.white.opacity(0.1) : .clear))
                .offset(x: t.minX - r.minX, y: t.minY - r.minY)
            }
            if model.spotlightQuery.isEmpty {
                Text("Apps, windows, files, bookmarks and history · sums like 12*3 · units like 5 km to mi")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: r.width - 32, alignment: .leading)
                    .offset(x: 16, y: r.height - 30)
            }
        }
        .frame(width: r.width, height: r.height, alignment: .topLeading)
        .floatingPanel(cornerRadius: 18, shadow: 30)
        .offset(x: r.minX, y: r.minY)
    }

    @ViewBuilder private func icon(_ res: SpotlightResult) -> some View {
        if let s = res.shortcut {
            AppIcon(shortcut: s, size: 28)
        } else if let image = res.image {
            Image(uiImage: image).resizable().clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: res.symbol).font(.system(size: 17, weight: .medium))
                .foregroundStyle(res.kind == .bookmark ? Color.yellow : res.kind == .answer ? Color.accentColor : Color.primary)
        }
    }
}
