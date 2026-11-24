import AVFoundation
import Combine
import UIKit
import WebKit

extension Notification.Name {
    static let apliteNowPlayingQuickLookChanged = Notification.Name("APLiteNowPlayingQuickLookChanged")
}

struct NowPlayingItem: Identifiable {
    let id: String
    let sourceID: String
    let title: String
    let subtitle: String
    let artwork: UIImage?
    let duration: TimeInterval
    let isVideo: Bool

    func withArtwork(_ image: UIImage) -> NowPlayingItem {
        NowPlayingItem(id: id, sourceID: sourceID, title: title, subtitle: subtitle,
                       artwork: image, duration: duration, isVideo: isVideo)
    }
}

/// Single source of truth for the media shown in the Dynamic Island. It never redraws the desktop: observers are
/// the isolated overlay view and the spectrum provider only. Notifications arrive on the main queue.
final class NowPlayingService: ObservableObject {
    static let shared = NowPlayingService()

    enum Control: String { case pill, playPause, backward, forward, close, progress }

    @Published private(set) var item: NowPlayingItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var isExpanded = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    /// Reported by the overlay view in its own window coordinates, used to route real-mouse clicks without
    /// installing any gesture recogniser that could swallow clicks on the desktop.
    private(set) var controlFrames: [Control: CGRect] = [:]

    var progress: Double {
        duration > 0 ? min(1, max(0, elapsed / duration)) : 0
    }

    private weak var webView: WKWebView?
    private weak var observedPlayer: AVPlayer?
    private var quickLookObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var clearWork: DispatchWorkItem?
    private var pointerDownControl: Control?
    private var pointerDownPoint: CGPoint?
    private var longPressWork: DispatchWorkItem?

    private static let toggleScript = """
    (() => {
      const ms = Array.from(document.querySelectorAll('video, audio'));
      const m = ms.find(x => !x.paused) || ms[0];
      if (m) { if (m.paused) m.play().catch(() => {}); else m.pause(); return 'ok'; }
      return 'none';
    })()
    """
    private static let pauseScript = "document.querySelectorAll('video,audio').forEach(m => m.pause())"

    private init() {
        NotificationCenter.default.addObserver(forName: .apliteNowPlayingQuickLookChanged,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.syncQuickLook()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.setExpanded(false)
        }
    }

    // MARK: Web media

    func updateWeb(playing: Bool, info: [String: Any]?, webView: WKWebView?) {
        guard let webView else { return }
        let sourceID = "web:" + String(ObjectIdentifier(webView).hashValue)
        if !playing {
            if item?.sourceID == sourceID { finish(sourceID: sourceID) }
            return
        }
        // With several web tabs playing, the focused one wins. A background tab can still become the pill when
        // nothing else is showing (e.g. the launcher is open and there is no focused window).
        if let current = item, current.sourceID.hasPrefix("web:"), current.sourceID != sourceID, isPlaying,
           DesktopModel.shared.focused?.webView !== webView { return }

        clearWork?.cancel(); clearWork = nil
        let title = (info?["title"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) ?? String(localized: "Now playing")
        let subtitle = (info?["subtitle"] as? String) ?? ""
        let newDuration = (info?["duration"] as? NSNumber)?.doubleValue ?? 0
        let currentTime = (info?["currentTime"] as? NSNumber)?.doubleValue ?? 0
        let isVideo = (info?["isVideo"] as? Bool) ?? false
        let artworkURL = info?["artwork"] as? String
        let changed = item?.sourceID != sourceID
        let newItem = NowPlayingItem(id: sourceID, sourceID: sourceID, title: title, subtitle: subtitle,
                                     artwork: changed ? nil : item?.artwork,
                                     duration: newDuration, isVideo: isVideo)
        if changed || item?.title != title || item?.subtitle != subtitle ||
           item?.duration != newDuration || item?.isVideo != isVideo { item = newItem }
        self.webView = webView
        if duration != newDuration { duration = newDuration }
        if changed || abs(elapsed - currentTime) > 0.5 { elapsed = currentTime }
        if !isPlaying { isPlaying = true }
        // A navigation replaces the page and drops the flag; re-apply it while the pill is expanded.
        if changed || isExpanded {
            webView.evaluateJavaScript("window.__ideskSpectrumWanted = \(isExpanded ? "true" : "false");",
                                       completionHandler: nil)
        }
        if changed {
            stopQuickLookObservation()
            AudioSpectrumProvider.shared.stopFileAnalysis()
            loadArtwork(artworkURL, for: sourceID, base: webView.url)
        }
    }

    private func loadArtwork(_ urlString: String?, for sourceID: String, base: URL?) {
        guard let urlString,
              let url = URL(string: urlString, relativeTo: base)?.absoluteURL ?? URL(string: urlString),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self, self.item?.sourceID == sourceID, let current = self.item else { return }
                self.item = current.withArtwork(image)
            }
        }.resume()
    }

    // MARK: Quick Look media

    func syncQuickLook() {
        guard let player = QuickLook.player else {
            if item?.sourceID == "quicklook" { finish(sourceID: "quicklook") }
            return
        }
        clearWork?.cancel(); clearWork = nil
        let sourceID = "quicklook"
        let asset = player.currentItem?.asset
        let title = asset?.commonMetadata.first(where: { $0.commonKey == .commonKeyTitle })?.stringValue
            ?? (asset as? AVURLAsset)?.url.deletingPathExtension().lastPathComponent
            ?? String(localized: "Now playing")
        let artist = asset?.commonMetadata.first(where: { $0.commonKey == .commonKeyArtist })?.stringValue ?? ""
        let artwork = asset?.commonMetadata.first(where: { $0.commonKey == .commonKeyArtwork })?.dataValue
            .flatMap { UIImage(data: $0) }
        let newDuration = player.currentItem?.duration.isValid == true ? player.currentItem!.duration.seconds : 0
        let changed = item?.sourceID != sourceID
        if changed { stopQuickLookObservation(); AudioSpectrumProvider.shared.stopFileAnalysis() }
        item = NowPlayingItem(id: sourceID, sourceID: sourceID, title: title, subtitle: artist,
                              artwork: artwork, duration: newDuration, isVideo: true)
        duration = newDuration
        elapsed = player.currentTime().seconds
        isPlaying = player.rate > 0
        webView = nil
        if changed {
            if let url = (asset as? AVURLAsset)?.url {
                AudioSpectrumProvider.shared.startFileAnalysis(url: url, player: player)
            }
            observedPlayer = player
            quickLookObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 2),
                                                               queue: .main) { [weak self] time in
                guard let self, self.item?.sourceID == sourceID else { return }
                if abs(time.seconds - self.elapsed) >= 0.5 { self.elapsed = time.seconds }
                let playing = player.rate > 0
                if self.isPlaying != playing { self.isPlaying = playing }
            }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
                self?.finish(sourceID: sourceID)
            }
        }
    }

    private func stopQuickLookObservation() {
        if let observer = quickLookObserver, let player = observedPlayer {
            player.removeTimeObserver(observer)
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        quickLookObserver = nil
        endObserver = nil
        observedPlayer = nil
    }

    private func finish(sourceID: String) {
        isPlaying = false
        setExpanded(false)   // shrink first, then fade out after the spring settles
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.item?.sourceID == sourceID, !self.isPlaying else { return }
            self.item = nil
            self.elapsed = 0
            self.duration = 0
            self.stopQuickLookObservation()
            AudioSpectrumProvider.shared.stopFileAnalysis()
        }
        clearWork?.cancel(); clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    // MARK: Controls

    func setExpanded(_ value: Bool) {
        guard isExpanded != value else { return }
        isExpanded = value
        AudioSpectrumProvider.shared.setExpanded(value)
        webView?.evaluateJavaScript("window.__ideskSpectrumWanted = \(value ? "true" : "false");",
                                    completionHandler: nil)
    }

    func toggleExpanded() { setExpanded(!isExpanded) }

    func togglePlayPause() {
        if item?.sourceID == "quicklook" {
            guard let player = QuickLook.player else { return }
            if player.rate > 0 { player.pause(); isPlaying = false } else { player.play(); isPlaying = true }
            return
        }
        if let webView {
            webView.evaluateJavaScript(Self.toggleScript) { [weak self] result, _ in
                if (result as? String) == "ok" { self?.isPlaying.toggle() }
            }
        } else {
            MediaControl.shared.playPause()
        }
    }

    func skip(by seconds: TimeInterval) { seek(to: elapsed + seconds) }

    func seek(progress: Double) { seek(to: progress * duration) }

    private func seek(to time: TimeInterval) {
        let clamped = min(max(time, 0), duration)
        if item?.sourceID == "quicklook" {
            QuickLook.player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        } else {
            webView?.evaluateJavaScript(
                "(() => { const ms = Array.from(document.querySelectorAll('video,audio')); const m = ms.find(x => !x.paused) || ms[0]; if (m) { try { m.currentTime = \(clamped); } catch (_) {} } })()",
                completionHandler: nil)
        }
        elapsed = clamped
    }

    func dismiss() {
        clearWork?.cancel(); clearWork = nil
        if item?.sourceID == "quicklook" { QuickLook.stop() }
        else { webView?.evaluateJavaScript(Self.pauseScript, completionHandler: nil) }
        stopQuickLookObservation()
        item = nil
        isPlaying = false
        isExpanded = false
        elapsed = 0
        duration = 0
        AudioSpectrumProvider.shared.stopFileAnalysis()
        AudioSpectrumProvider.shared.setExpanded(false)
    }

    // MARK: Geometry and real-mouse routing

    func setFrame(_ rect: CGRect, for control: Control) { controlFrames[control] = rect }

    private func control(at point: CGPoint) -> Control? {
        for control in [Control.playPause, .backward, .forward, .close, .progress, .pill] {
            if let rect = controlFrames[control], rect.contains(point) { return control }
        }
        return nil
    }

    /// A physical mouse press inside the pill is consumed here instead of starting a desktop drag. No gesture
    /// recogniser is added to the pill, so global clicks keep working everywhere else.
    func pointerDown(at point: CGPoint) -> Bool {
        guard item != nil, let control = control(at: point) else { return false }
        pointerDownControl = control
        pointerDownPoint = point
        if control == .pill {
            let work = DispatchWorkItem { [weak self] in
                self?.setExpanded(true)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
            longPressWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
        return true
    }

    @discardableResult
    func pointerUp(at point: CGPoint) -> Bool {
        guard let down = pointerDownControl else { return false }
        pointerDownControl = nil
        let start = pointerDownPoint
        pointerDownPoint = nil
        longPressWork?.cancel(); longPressWork = nil
        guard control(at: point) == down else { return true }
        switch down {
        case .pill: toggleExpanded()
        case .playPause: togglePlayPause()
        case .backward: skip(by: -10)
        case .forward: skip(by: 10)
        case .close: dismiss()
        case .progress:
            if let rect = controlFrames[.progress], rect.width > 0, let start {
                seek(progress: (start.x - rect.minX) / rect.width)
            }
        }
        return true
    }

    func secondaryClick(at point: CGPoint) -> Bool {
        guard item != nil, let control = control(at: point), control == .pill else { return false }
        toggleExpanded()
        return true
    }
}
