import SwiftUI
import WebKit

/// Downloads from web pages, into Files (Documents/Downloads). While any is listed, a button with a progress ring
/// sits on the taskbar next to the tray; it opens the Downloads panel: progress, pause / resume, cancel, open.
final class Downloads: NSObject, ObservableObject, WKDownloadDelegate {
    static let shared = Downloads()

    enum State { case running, paused, done, failed }

    struct Item: Identifiable {
        let id = UUID()
        var name: String
        var url: URL
        var fraction: Double = 0
        var received: Int64 = 0
        var total: Int64 = 0
        var state: State = .running
        var resumeData: Data?
        weak var webView: WKWebView?
    }

    @Published private(set) var items: [Item] = [] {
        // The taskbar makes room for its button when the first download starts and when the list empties.
        didSet {
            if items.isEmpty != oldValue.isEmpty { DesktopModel.shared.objectWillChange.send() }
        }
    }
    private var tasks: [UUID: WKDownload] = [:]
    private var observations: [UUID: NSKeyValueObservation] = [:]
    /// The item whose download is being resumed (WebKit may ask for its destination again).
    private var resuming: UUID?

    /// Downloads in progress, for the Files page.
    var active: [(name: String, percent: Int)] {
        items.filter { $0.state == .running || $0.state == .paused }
            .map { ($0.name, Int(($0.fraction * 100).rounded())) }
    }

    var isBusy: Bool { items.contains { $0.state == .running } }
    var hasPaused: Bool { items.contains { $0.state == .paused } }
    /// The progress of everything running together (for the taskbar ring).
    var overallFraction: Double {
        let running = items.filter { $0.state == .running || $0.state == .paused }
        guard !running.isEmpty else { return 1 }
        return running.map(\.fraction).reduce(0, +) / Double(running.count)
    }

    private func index(of download: WKDownload) -> Int? {
        guard let id = tasks.first(where: { $0.value === download })?.key else { return nil }
        return items.firstIndex { $0.id == id }
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping @MainActor (URL?) -> Void) {
        if let id = resuming, let i = items.firstIndex(where: { $0.id == id }) {
            resuming = nil
            try? FileManager.default.removeItem(at: items[i].url)
            completionHandler(items[i].url)
            return
        }
        let url = FileStore.uniqueURL(in: FileStore.downloads, name: suggestedFilename)
        var item = Item(name: url.lastPathComponent, url: url)
        item.webView = download.webView
        item.total = response.expectedContentLength
        items.insert(item, at: 0)
        track(download, as: item.id)
        DesktopModel.shared.showToast(String(localized: "Downloading \(url.lastPathComponent)…"))
        completionHandler(url)
        DesktopModel.shared.refreshFilesPages()
    }

    private func track(_ download: WKDownload, as id: UUID) {
        tasks[id] = download
        download.delegate = self
        var last = -1, lastBytes: Int64 = 0
        observations[id] = download.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            let percent = Int(p.fractionCompleted * 100)
            let received = p.completedUnitCount, total = p.totalUnitCount
            DispatchQueue.main.async {
                // Every percent, or every half megabyte for big files (the size shown keeps moving).
                guard let self, percent != last || received - lastBytes >= 512_000,
                      let i = self.items.firstIndex(where: { $0.id == id }) else { return }
                let newPercent = percent != last
                last = percent
                lastBytes = received
                self.items[i].fraction = p.fractionCompleted
                self.items[i].received = received
                if total > 0 { self.items[i].total = total }
                // Recomputing folder sizes means walking the file tree. Every 5 % did that up to
                // 20× per download; every 20 % keeps the Files page fresh without the I/O storm.
                if newPercent && percent % 20 == 0 { DesktopModel.shared.refreshFilesPages() }
            }
        }
    }

    private func finish(_ download: WKDownload, _ state: State) -> Item? {
        guard let i = index(of: download) else { return nil }
        let id = items[i].id
        tasks[id] = nil
        observations[id] = nil
        items[i].state = state
        if state == .done { items[i].fraction = 1 }
        let item = items[i]          // capture before trimming shifts indices
        trimOldFinished()
        return item
    }

    /// Keep the history bounded: failed downloads carry resumeData, so a long session used to
    /// retain every partial file blob forever. The list is informational, not an archive.
    private func trimOldFinished() {
        let finished = items.indices.filter { items[$0].state == .done || items[$0].state == .failed }
        guard finished.count > 50 else { return }
        for i in finished.prefix(finished.count - 50).reversed() { items.remove(at: i) }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let item = finish(download, .done) else { return }
        DesktopModel.shared.showToast(String(localized: "Downloaded \(item.name)"))
        DesktopModel.shared.refreshFilesPages()
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let i = index(of: download), resuming == items[i].id { resuming = nil }
        // A pause cancels the download too: that one keeps its resume data and stays paused.
        if let i = index(of: download), items[i].state == .paused {
            tasks[items[i].id] = nil
            observations[items[i].id] = nil
            if let resumeData { items[i].resumeData = resumeData }
            return
        }
        guard let item = finish(download, .failed) else { return }
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].resumeData = resumeData }
        DesktopModel.shared.showToast(String(localized: "Could not download \(item.name)."))
        DesktopModel.shared.refreshFilesPages()
    }

    // MARK: Actions

    func pause(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].state == .running, let task = tasks[id] else { return }
        items[i].state = .paused
        task.cancel { [weak self] data in
            DispatchQueue.main.async {
                guard let self, let i = self.items.firstIndex(where: { $0.id == id }) else { return }
                self.items[i].resumeData = data
                if data == nil { self.items[i].state = .failed }
            }
        }
    }

    /// Resumes a paused (or failed) download where it stopped, or starts it again when it cannot.
    func resume(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        // Never resume in an unrelated tab: the focused window may belong to a different origin.
        let name = items[i].name
        guard let data = items[i].resumeData, let web = items[i].webView else {
            showFailure(name)
            return
        }
        items[i].state = .running
        items[i].resumeData = nil
        resuming = id
        web.resumeDownload(fromResumeData: data) { [weak self] download in
            guard let self else { return }
            guard let download else {
                // No WKDownload means the resume never started: do not leave `resuming` to hijack the
                // next unrelated download's destination, and keep the data so the user can try again.
                self.resuming = nil
                if let index = self.items.firstIndex(where: { $0.id == id }) {
                    self.items[index].state = .failed
                    self.items[index].resumeData = data
                }
                self.showFailure(name)
                return
            }
            self.track(download, as: id)
        }
    }

    private func showFailure(_ name: String) {
        DesktopModel.shared.showToast(String(localized: "Could not resume \(name). Download it again from the page."))
    }

    func cancel(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        tasks[id]?.cancel(nil)
        tasks[id] = nil
        observations[id] = nil
        if items[i].state != .done { try? FileManager.default.removeItem(at: items[i].url) }
        items.remove(at: i)
        DesktopModel.shared.refreshFilesPages()
    }

    func clearFinished() {
        items.removeAll { $0.state == .done || $0.state == .failed }
    }
}

// MARK: - Panel

enum DownloadsPanel {
    static let width: CGFloat = 400
    static let header: CGFloat = 46
    static let row: CGFloat = 62
    static let padding: CGFloat = 8
    static let maxRows = 6
    static let button: CGFloat = 30
}

extension DesktopModel {
    /// The taskbar button (left of the tray) while there are downloads.
    var downloadsButtonRect: CGRect? {
        guard !Downloads.shared.items.isEmpty else { return nil }
        let h = min(38, dockHeight - 10)
        return CGRect(x: windowListButtonRect.minX - 44, y: dockY + (dockHeight - h) / 2, width: 40, height: h)
    }

    var downloadsRect: CGRect {
        let n = CGFloat(min(DownloadsPanel.maxRows, max(1, Downloads.shared.items.count)))
        let h = DownloadsPanel.padding * 2 + DownloadsPanel.header + n * DownloadsPanel.row
        return CGRect(x: screenSize.width - DownloadsPanel.width - 12, y: taskbarTop - h - 8, width: DownloadsPanel.width, height: h)
    }

    func downloadRowRect(_ i: Int) -> CGRect {
        let r = downloadsRect
        return CGRect(x: r.minX + DownloadsPanel.padding, y: r.minY + DownloadsPanel.padding + DownloadsPanel.header + CGFloat(i) * DownloadsPanel.row,
                      width: r.width - DownloadsPanel.padding * 2, height: DownloadsPanel.row)
    }

    /// The two buttons at the right of a row: [0] pause / resume / show, [1] cancel / remove.
    func downloadButtonRect(_ i: Int, _ b: Int) -> CGRect {
        let row = downloadRowRect(i), s = DownloadsPanel.button
        return CGRect(x: row.maxX - 8 - s * CGFloat(2 - b) - 6 * CGFloat(1 - b), y: row.midY - s / 2, width: s, height: s)
    }

    var downloadsClearRect: CGRect {
        let r = downloadsRect
        return CGRect(x: r.maxX - DownloadsPanel.padding - 120, y: r.minY + DownloadsPanel.padding + 8, width: 112, height: 30)
    }

    func clickDownloads(at p: CGPoint) {
        let all = Downloads.shared.items
        if downloadsClearRect.contains(p) { Downloads.shared.clearFinished(); if Downloads.shared.items.isEmpty { showDownloads = false }; return }
        for i in all.prefix(DownloadsPanel.maxRows).indices where downloadRowRect(i).contains(p) {
            let item = all[i]
            if downloadButtonRect(i, 1).insetBy(dx: -3, dy: -3).contains(p) {
                if item.state == .done || item.state == .failed {
                    Downloads.shared.clearItem(item.id)
                } else {
                    Downloads.shared.cancel(item.id)
                }
                if Downloads.shared.items.isEmpty { showDownloads = false }
                return
            }
            if downloadButtonRect(i, 0).insetBy(dx: -3, dy: -3).contains(p) {
                switch item.state {
                case .running: Downloads.shared.pause(item.id)
                case .paused, .failed: Downloads.shared.resume(item.id)
                case .done: showDownloadInFiles(item)
                }
                return
            }
            if item.state == .done, let path = FileStore.relativePath(of: item.url) {
                showDownloads = false
                openFile(path)
            }
            return
        }
        if !downloadsRect.contains(p) { showDownloads = false }
    }

    private func showDownloadInFiles(_ item: Downloads.Item) {
        showDownloads = false
        openPage(.files)
        if let w = windows.last(where: { $0.systemPage == .files }) {
            w.showFolder("")
            w.selectedFile = FileStore.relativePath(of: item.url)
        }
    }
}

extension Downloads {
    /// Takes a finished (or failed) download off the list; the file stays in Files.
    func clearItem(_ id: UUID) { items.removeAll { $0.id == id } }
}

/// The taskbar button: a download arrow inside a ring that fills as the downloads progress.
struct DownloadsButton: View {
    @ObservedObject var downloads = Downloads.shared
    let hovered: Bool
    let open: Bool

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 3)
            Circle().trim(from: 0, to: downloads.overallFraction)
                .stroke(downloads.isBusy ? Color.accentColor : downloads.hasPaused ? Color.orange : Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: downloads.isBusy ? "arrow.down" : downloads.hasPaused ? "pause.fill" : "checkmark")
                .font(.system(size: 11, weight: .bold))
        }
        .frame(width: 24, height: 24)
        .frame(width: 42, height: Layout.buttonHeight)
        .background(RoundedRectangle(cornerRadius: 8).fill(open ? Color.white.opacity(0.18) : hovered ? Color.white.opacity(0.12) : .clear))
    }
}

struct DownloadsPanelView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var cursor: CursorModel
    @ObservedObject var downloads = Downloads.shared

    var body: some View {
        let r = model.downloadsRect
        let p = cursor.position
        ZStack(alignment: .topLeading) {
            Text("Downloads").font(.system(size: 16, weight: .semibold))
                .frame(height: DownloadsPanel.header).offset(x: DownloadsPanel.padding + 10, y: DownloadsPanel.padding)
            let clear = model.downloadsClearRect
            Text("Clear finished").font(.system(size: 12, weight: .medium))
                .frame(width: clear.width, height: clear.height)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(clear.contains(p) ? 0.18 : 0.08)))
                .offset(x: clear.minX - r.minX, y: clear.minY - r.minY)
            if downloads.items.isEmpty {
                Text("Nothing downloading").font(.system(size: 13)).foregroundStyle(.secondary)
                    .offset(x: 20, y: DownloadsPanel.padding + DownloadsPanel.header + 20)
            }
            ForEach(Array(downloads.items.prefix(DownloadsPanel.maxRows).enumerated()), id: \.element.id) { i, item in
                let t = model.downloadRowRect(i)
                HStack(spacing: 10) {
                    Image(systemName: FileStore.iconSymbol(for: item.url.pathExtension)).font(.system(size: 20)).frame(width: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        if item.state == .running || item.state == .paused {
                            ProgressView(value: item.fraction).tint(item.state == .paused ? .orange : .accentColor)
                        }
                        Text(verbatim: Self.detail(item)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    ForEach(0..<2, id: \.self) { b in
                        let br = model.downloadButtonRect(i, b)
                        Image(systemName: Self.symbol(item, b)).font(.system(size: 12, weight: .semibold))
                            .frame(width: br.width, height: br.height)
                            .background(Circle().fill(Color.white.opacity(br.contains(p) ? 0.22 : 0.1)))
                    }
                }
                .padding(.horizontal, 8)
                .frame(width: t.width, height: t.height)
                .background(RoundedRectangle(cornerRadius: 9).fill(t.contains(p) ? Color.white.opacity(0.06) : .clear))
                .offset(x: t.minX - r.minX, y: t.minY - r.minY)
            }
        }
        .frame(width: r.width, height: r.height, alignment: .topLeading)
        .floatingPanel(cornerRadius: 16)
        .offset(x: r.minX, y: r.minY)
    }

    static func symbol(_ item: Downloads.Item, _ b: Int) -> String {
        if b == 1 { return item.state == .done || item.state == .failed ? "xmark" : "stop.fill" }
        switch item.state {
        case .running: return "pause.fill"
        case .paused, .failed: return "arrow.clockwise"
        case .done: return "magnifyingglass"
        }
    }

    static func detail(_ item: Downloads.Item) -> String {
        let f = ByteCountFormatter()
        let got = f.string(fromByteCount: item.received)
        let total = item.total > 0 ? f.string(fromByteCount: item.total) : "?"
        switch item.state {
        case .running: return "\(got) / \(total)"
        case .paused: return String(localized: "Paused") + " · \(got) / \(total)"
        case .done: return String(localized: "Done") + (item.total > 0 ? " · \(total)" : "")
        case .failed: return String(localized: "Failed")
        }
    }
}
