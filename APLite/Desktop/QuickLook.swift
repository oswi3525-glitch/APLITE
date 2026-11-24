import SwiftUI
import PDFKit
import AVFoundation

/// Quick Look: a preview of a file from Files, over the desktop (Space opens and closes it, ← → / ↑ ↓ go to the
/// other files, Esc or a click outside closes it). Drawn by APLite on the external display: images, PDFs, video and
/// audio, and text files; anything else shows its name and size.
enum QuickLook {
    enum Kind { case image, pdf, media, text, other }

    static func kind(of url: URL) -> Kind {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "bmp", "tif", "tiff": return .image
        case "pdf": return .pdf
        case "mp4", "mov", "m4v", "mp3", "m4a", "wav", "aac", "aiff", "caf": return .media
        case "txt", "md", "csv", "json", "log", "xml", "yml", "yaml", "plist", "strings": return .text
        default: return .other
        }
    }

    /// What the wheel and the trackpad scroll while a PDF or a text file is shown.
    fileprivate static weak var scrollTarget: UIScrollView?
    static private(set) var player: AVPlayer?

    /// Wheel / two-finger scroll over the preview (dy > 0 moves the content up, as in a web page).
    static func scroll(dx: CGFloat, dy: CGFloat) {
        guard let s = scrollTarget else { return }
        let inset = s.adjustedContentInset
        let maxX = max(-inset.left, s.contentSize.width - s.bounds.width + inset.right)
        let maxY = max(-inset.top, s.contentSize.height - s.bounds.height + inset.bottom)
        s.setContentOffset(CGPoint(x: min(max(-inset.left, s.contentOffset.x + dx), maxX),
                                   y: min(max(-inset.top, s.contentOffset.y + dy), maxY)), animated: false)
    }

    /// The preview closed (or moved to another file): stop the sound.
    static func stop() {
        player?.pause()
        player = nil
        NotificationCenter.default.post(name: .apliteNowPlayingQuickLookChanged, object: nil)
    }

    /// The audio session came back after an interruption or a route change: resume a preview that
    /// was still visible (the preview has no pause control, so it was meant to be playing).
    static func resume() {
        guard let player, player.rate == 0,
              let duration = player.currentItem?.duration, duration.isValid,
              player.currentTime() < duration else { return }
        player.play()
        NotificationCenter.default.post(name: .apliteNowPlayingQuickLookChanged, object: nil)
    }

    /// True while a media preview is actually playing (audio session should stay active).
    static var isActive: Bool { player != nil }

    /// Drops the single decoded preview image under memory pressure.
    static func clearImageCache() { cached = nil }

    fileprivate static func image(at url: URL) -> UIImage? {
        if cached?.url == url { return cached?.image }
        let image = UIImage(contentsOfFile: url.path)
        cached = (url, image)
        return image
    }

    /// Decode an image preview off the main thread as soon as it is selected, so SwiftUI's body
    /// finds it already cached instead of decoding a large photo during a layout pass.
    static func preload(_ url: URL) {
        guard kind(of: url) == .image, cached?.url != url else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let image = UIImage(contentsOfFile: url.path)
            DispatchQueue.main.async { cached = (url, image) }
        }
    }

    private static var cached: (url: URL, image: UIImage?)?
}

struct QuickLookView: View {
    let url: URL
    let rect: CGRect

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(.secondary)
                Text(url.lastPathComponent).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(size).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("Space or Esc closes · ← → other files")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .frame(width: rect.width, height: rect.height)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .offset(x: rect.minX, y: rect.minY)
        .environment(\.colorScheme, .dark)
        .onReceive(NotificationCenter.default.publisher(for: .apliteAudioDidResume)) { _ in QuickLook.resume() }
    }

    @ViewBuilder private var content: some View {
        switch QuickLook.kind(of: url) {
        case .image:
            if let image = QuickLook.image(at: url) {
                Image(uiImage: image).resizable().scaledToFit().padding(12)
            } else {
                unavailable
            }
        case .pdf: PDFPreview(url: url)
        case .media: MediaPreview(url: url)
        case .text: TextPreview(url: url)
        case .other: unavailable
        }
    }

    private var unavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 64)).foregroundStyle(.secondary)
            Text(url.lastPathComponent).font(.system(size: 16, weight: .medium))
            Text("No preview for this kind of file. Double-click it in Files to open it.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding()
    }

    private var symbol: String {
        switch QuickLook.kind(of: url) {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .media: return "play.rectangle"
        case .text: return "doc.text"
        case .other: return "doc"
        }
    }

    private var size: String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter().string(fromByteCount: Int64(bytes))
    }
}

private struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(white: 0.16, alpha: 1)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
        QuickLook.scrollTarget = view.subviews.compactMap { $0 as? UIScrollView }.first
    }
}

private struct TextPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.backgroundColor = .clear
        view.textColor = UIColor(white: 0.92, alpha: 1)
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.textContainerInset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            // Only the start of a big file: enough to see what it is.
            let data = (try? FileHandle(forReadingFrom: url).readData(ofLength: 512 * 1024)) ?? Data()
            view.text = String(decoding: data, as: UTF8.self)
            view.contentOffset = .zero
        }
        QuickLook.scrollTarget = view
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var url: URL? }
}

/// Video or sound, playing as soon as it is shown (the preview has no controls: Space closes it).
private struct MediaPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView { PlayerView() }

    func updateUIView(_ view: PlayerView, context: Context) {
        guard view.url != url else { return }
        view.url = url
        QuickLook.stop()
        AudioSessionManager.shared.activatePlayback(reason: "Quick Look media")
        let player = AVPlayer(url: url)
        QuickLook.player = player
        view.playerLayer.player = player
        player.play()
        NotificationCenter.default.post(name: .apliteNowPlayingQuickLookChanged, object: nil)
    }

    final class PlayerView: UIView {
        var url: URL?
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
