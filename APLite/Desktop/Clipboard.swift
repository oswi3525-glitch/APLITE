import SwiftUI

/// What was copied on the desktop (⌘ + Shift + V shows it), newest first: text copied in web pages and iOS apps
/// with ⌘C / ⌘X, links and addresses from the menus, screenshots, Spotlight answers.
///
/// APLite never reads the clipboard on its own: when another app (or Universal Clipboard from a Mac) put something
/// there, reading it makes iOS ask the user to allow pasting and blocks APLite until they answer. So only copies
/// APLite makes are noted. Only pinned text is kept after APLite quits; the rest (it may be a password) stays in memory.
final class ClipboardHistory: ObservableObject {
    static let shared = ClipboardHistory()

    struct Item: Identifiable {
        let id = UUID()
        var text: String?
        var image: UIImage?
        var date = Date()
        var pinned = false
    }

    @Published private(set) var items: [Item] = []
    private static let pinnedKey = "iDesk.clipboardPinned"
    private static let limit = 40

    private init() {
        items = (UserDefaults.standard.stringArray(forKey: Self.pinnedKey) ?? []).map { Item(text: $0, pinned: true) }
    }

    /// Puts text on the clipboard and notes it.
    func copy(_ text: String) {
        UIPasteboard.general.string = text
        add(text: text)
    }

    func copy(_ url: URL) {
        UIPasteboard.general.url = url
        add(text: url.absoluteString)
    }

    func copy(_ image: UIImage) {
        UIPasteboard.general.image = image
        add(image: image)
    }

    /// An iOS app was asked to copy (⌘C / ⌘X): it runs inside APLite, so what it put on the clipboard can be read
    /// without iOS asking. Read only if the clipboard did change since `before` (otherwise it still holds what
    /// another app copied).
    func noteAppCopy(since before: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            let pb = UIPasteboard.general
            guard let self, pb.changeCount != before else { return }
            if pb.hasImages, let image = pb.image { self.add(image: image) }
            else if pb.hasStrings, let s = pb.string { self.add(text: s) }
        }
    }

    func add(text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count < 100_000 else { return }
        if let i = items.firstIndex(where: { $0.text == text }) {
            var item = items.remove(at: i)
            item.date = Date()
            items.insert(item, at: 0)
        } else {
            items.insert(Item(text: text), at: 0)
        }
        trim()
    }

    func add(image: UIImage) {
        // The same picture copied twice in a row: once.
        if let first = items.first?.image, first.size == image.size, first.pngData() == image.pngData() { return }
        let maxSide: CGFloat = 1600
        let s = image.size, k = min(1, maxSide / max(s.width, s.height, 1))
        let kept = k < 1 ? UIGraphicsImageRenderer(size: CGSize(width: s.width * k, height: s.height * k)).image { _ in
            image.draw(in: CGRect(origin: .zero, size: CGSize(width: s.width * k, height: s.height * k)))
        } : image
        items.insert(Item(image: kept), at: 0)
        trim()
    }

    func togglePin(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clearUnpinned() {
        items.removeAll { !$0.pinned }
    }

    /// Puts an item back on the clipboard (and at the top of the list) without counting it as a new copy.
    func use(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: i)
        items.insert(item, at: 0)
        if let image = item.image { UIPasteboard.general.image = image } else if let t = item.text { UIPasteboard.general.string = t }
    }

    /// Pinned first, then the rest newest first.
    var ordered: [Item] { items.filter(\.pinned) + items.filter { !$0.pinned } }

    private func trim() {
        var unpinned = 0
        items = items.filter { item in
            if item.pinned { return true }
            unpinned += 1
            return unpinned <= Self.limit
        }
    }

    private func save() {
        UserDefaults.standard.set(items.filter(\.pinned).compactMap(\.text), forKey: Self.pinnedKey)
    }
}

enum ClipboardPanel {
    static let width: CGFloat = 560
    static let header: CGFloat = 48
    static let row: CGFloat = 56
    static let padding: CGFloat = 8
    static let visibleRows = 8
}

extension DesktopModel {
    func toggleClipboard() {
        guard isExternalConnected else { return }
        let open = !showClipboard
        closePanels()
        clipboardIndex = 0
        showClipboard = open
    }

    /// The rows shown: a window of the list that keeps the selected one in view.
    var clipboardVisible: (start: Int, items: [ClipboardHistory.Item]) {
        let all = ClipboardHistory.shared.ordered
        let n = ClipboardPanel.visibleRows
        let start = max(0, min(clipboardIndex - n + 1, all.count - n))
        return (start, Array(all.dropFirst(start).prefix(n)))
    }

    var clipboardRect: CGRect {
        let rows = CGFloat(max(1, clipboardVisible.items.count))
        let h = ClipboardPanel.padding * 2 + ClipboardPanel.header + rows * ClipboardPanel.row
        let w = min(ClipboardPanel.width, screenSize.width - 40)
        return CGRect(x: (screenSize.width - w) / 2, y: max(16, screenSize.height * 0.14), width: w, height: h)
    }

    /// Row `i` of the visible ones.
    func clipboardRowRect(_ i: Int) -> CGRect {
        let r = clipboardRect
        return CGRect(x: r.minX + ClipboardPanel.padding, y: r.minY + ClipboardPanel.padding + ClipboardPanel.header + CGFloat(i) * ClipboardPanel.row,
                      width: r.width - ClipboardPanel.padding * 2, height: ClipboardPanel.row)
    }

    var clipboardClearRect: CGRect {
        let r = clipboardRect
        return CGRect(x: r.maxX - ClipboardPanel.padding - 92, y: r.minY + ClipboardPanel.padding + 8, width: 84, height: 30)
    }

    func moveClipboardSelection(_ delta: Int) {
        let n = ClipboardHistory.shared.items.count
        guard n > 0 else { return }
        clipboardIndex = min(max(0, clipboardIndex + delta), n - 1)
    }

    /// Pastes an item (by its index in the whole list) into the window in front.
    func pasteFromClipboard(_ index: Int? = nil) {
        let all = ClipboardHistory.shared.ordered
        let i = index ?? clipboardIndex
        guard all.indices.contains(i) else { return }
        showClipboard = false
        ClipboardHistory.shared.use(all[i].id)
        DispatchQueue.main.async { [weak self] in self?.paste() }
    }

    func clickClipboard(at p: CGPoint) {
        if clipboardClearRect.contains(p) { ClipboardHistory.shared.clearUnpinned(); clipboardIndex = 0; return }
        let visible = clipboardVisible
        if let i = visible.items.indices.first(where: { clipboardRowRect($0).contains(p) }) { pasteFromClipboard(visible.start + i); return }
        if !clipboardRect.contains(p) { showClipboard = false }
    }

    /// Right click on an item: pin, unpin, delete.
    func clipboardMenu(at p: CGPoint) -> [MenuItem]? {
        let visible = clipboardVisible
        guard let i = visible.items.indices.first(where: { clipboardRowRect($0).contains(p) }) else { return nil }
        let item = visible.items[i], index = visible.start + i
        return [
            MenuItem("Paste", "doc.on.clipboard") { [weak self] in self?.pasteFromClipboard(index) },
            MenuItem(item.pinned ? "Unpin" : "Pin", item.pinned ? "pin.slash" : "pin") { ClipboardHistory.shared.togglePin(item.id) },
            .separator,
            MenuItem("Delete", "trash") { ClipboardHistory.shared.remove(item.id) },
        ]
    }
}

struct ClipboardPanelView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var cursor: CursorModel
    @ObservedObject var history = ClipboardHistory.shared

    var body: some View {
        let r = model.clipboardRect
        let visible = model.clipboardVisible
        ZStack(alignment: .topLeading) {
            HStack(spacing: 10) {
                Image(systemName: "list.clipboard").font(.system(size: 17, weight: .semibold))
                Text("Clipboard").font(.system(size: 16, weight: .semibold))
                Text("↑ ↓ · Enter: paste · right-click: pin").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(width: r.width - ClipboardPanel.padding * 2 - 100, height: ClipboardPanel.header, alignment: .leading)
            .offset(x: ClipboardPanel.padding + 10, y: ClipboardPanel.padding)

            let clear = model.clipboardClearRect
            Text("Clear all").font(.system(size: 12, weight: .medium))
                .frame(width: clear.width, height: clear.height)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(clear.contains(cursor.position) ? 0.18 : 0.08)))
                .offset(x: clear.minX - r.minX, y: clear.minY - r.minY)

            if visible.items.isEmpty {
                Text("Nothing copied yet. Text and pictures you copy on the desktop show here.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .frame(width: r.width - 40, height: ClipboardPanel.row, alignment: .leading)
                    .offset(x: 20, y: ClipboardPanel.padding + ClipboardPanel.header)
            }
            ForEach(Array(visible.items.enumerated()), id: \.element.id) { i, item in
                let t = model.clipboardRowRect(i)
                let selected = visible.start + i == model.clipboardIndex
                HStack(spacing: 12) {
                    if let image = item.image {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 64, height: 42).clipShape(RoundedRectangle(cornerRadius: 6))
                        (Text("Picture") + Text(verbatim: " · \(Int(image.size.width))×\(Int(image.size.height))")).font(.system(size: 13))
                    } else {
                        Image(systemName: "text.alignleft").frame(width: 24).foregroundStyle(.secondary)
                        Text(verbatim: (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 13)).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    if item.pinned { Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(.yellow) }
                    Text(item.date, style: .relative).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(width: t.width, height: t.height)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.55) : t.contains(cursor.position) ? Color.white.opacity(0.1) : .clear))
                .offset(x: t.minX - r.minX, y: t.minY - r.minY)
            }
        }
        .frame(width: r.width, height: r.height, alignment: .topLeading)
        .floatingPanel(cornerRadius: 18, shadow: 30)
        .offset(x: r.minX, y: r.minY)
    }
}
