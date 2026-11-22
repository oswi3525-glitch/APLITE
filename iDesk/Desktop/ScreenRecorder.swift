import SwiftUI
import AVFoundation
import MediaPlayer

/// Records the external display to a video (⌘ + Shift + 5, the desktop menu, or the quick panel): 20 frames a
/// second at the display's size, pointer included. While recording a red button with the time shows on the taskbar;
/// clicking it (or ⌘ + Shift + 5 again) stops, and the video goes to Photos and Files.
final class ScreenRecorder: ObservableObject {
    static let shared = ScreenRecorder()
    @Published private(set) var isRecording = false
    @Published private(set) var started: Date?

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var link: CADisplayLink?
    private var url: URL?
    private var size: CGSize = .zero
    private var frames: Int64 = 0
    private static let fps: Int32 = 20

    func toggle() { isRecording ? stop() : start() }

    func start() {
        let model = DesktopModel.shared
        guard !isRecording, model.isExternalConnected, let view = ExternalSceneDelegate.desktopView else { return }
        // Even sizes (H.264), at most 1920 wide.
        let k = min(1, 1920 / max(1, view.bounds.width))
        size = CGSize(width: (view.bounds.width * k / 2).rounded() * 2, height: (view.bounds.height * k / 2).rounded() * 2)
        let name = String(localized: "Screen recording") + " " + Self.stamp() + ".mp4"
        let url = FileStore.uniqueURL(in: FileStore.downloads, name: name)
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000, AVVideoMaxKeyFrameIntervalKey: 40],
            ])
            input.expectsMediaDataInRealTime = true
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
            ])
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            writer.startSession(atSourceTime: .zero)
            self.writer = writer; self.input = input; self.adaptor = adaptor; self.url = url
        } catch {
            model.showToast(String(localized: "Could not start recording: \(error.localizedDescription)"))
            return
        }
        frames = 0
        started = Date()
        isRecording = true
        let link = CADisplayLink(target: Tick(self), selector: #selector(Tick.fire))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: Float(Self.fps), maximum: Float(Self.fps), preferred: Float(Self.fps))
        link.add(to: .main, forMode: .common)
        self.link = link
        model.showToast(String(localized: "Recording the screen. ⌘ + Shift + 5 or the red button stops it."))
        model.objectWillChange.send()
    }

    fileprivate func capture() {
        // Each frame's drawing makes temporary objects; without a pool per frame they pile up until recording stops.
        autoreleasepool { captureFrame() }
    }

    private func captureFrame() {
        guard isRecording, let view = ExternalSceneDelegate.desktopView, let adaptor, let input, input.isReadyForMoreMediaData,
              let pool = adaptor.pixelBufferPool else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                               bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: size.width / view.bounds.width, y: -size.height / view.bounds.height)
            UIGraphicsPushContext(ctx)
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
            UIGraphicsPopContext()
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(value: frames, timescale: Self.fps))
        frames += 1
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        started = nil
        link?.invalidate()
        link = nil
        let model = DesktopModel.shared
        model.objectWillChange.send()
        guard let writer, let input, let url else { return }
        input.markAsFinished()
        writer.finishWriting { [weak self] in
            DispatchQueue.main.async {
                self?.writer = nil; self?.input = nil; self?.adaptor = nil; self?.url = nil
                guard writer.status == .completed else {
                    model.showToast(String(localized: "The recording could not be saved.")); return
                }
                UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
                model.showToast(String(localized: "Screen recording saved to Photos and Files"))
                model.refreshFilesPages()
            }
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"; return f.string(from: Date())
    }

    private final class Tick: NSObject {
        weak var recorder: ScreenRecorder?
        init(_ r: ScreenRecorder) { recorder = r }
        @objc func fire(_ link: CADisplayLink) {
            guard let recorder else { link.invalidate(); return }
            recorder.capture()
        }
    }
}

extension DesktopModel {
    /// The red stop button on the taskbar while recording (left of the downloads button and the tray).
    var recordButtonRect: CGRect? {
        guard ScreenRecorder.shared.isRecording else { return nil }
        let right = downloadsButtonRect?.minX ?? taskManagerButtonRect.minX
        let h = min(36, dockHeight - 10)
        return CGRect(x: right - 88, y: dockY + (dockHeight - h) / 2, width: 84, height: h)
    }
}

struct RecordButton: View {
    @ObservedObject var recorder = ScreenRecorder.shared
    let hovered: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let s = Int(ctx.date.timeIntervalSince(recorder.started ?? ctx.date))
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 9, height: 9)
                Text(String(format: "%d:%02d", s / 60, s % 60)).font(.system(size: 12, weight: .semibold).monospacedDigit())
                Image(systemName: "stop.fill").font(.system(size: 9))
            }
            .frame(width: 86, height: Layout.buttonHeight - 4)
            .background(Capsule().fill(Color.red.opacity(hovered ? 0.45 : 0.28)))
        }
    }
}

// MARK: - Volume and media keys

/// The iPhone's volume shown on the big screen when it changes (buttons, or the keyboard's volume keys), and the
/// keyboard's media keys: F8 / play-pause plays or pauses what is playing on the desktop.
final class MediaControl: NSObject, ObservableObject {
    static let shared = MediaControl()
    @Published private(set) var hud: (symbol: String, level: Float?)?
    /// Current system mute state (the Control Center tile and the HUD both read this).
    var isMuted: Bool { AVAudioSession.sharedInstance().outputVolume <= 0.001 }
    private var hudWork: DispatchWorkItem?
    private var volumeObservation: NSKeyValueObservation?
    private let volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 10, height: 10))
    private var mutedLevel: Float?

    func start() {
        // The session category and activation belong to AudioSessionManager (it also handles
        // interruptions and route changes). We only observe the system volume here.
        let session = AVAudioSession.sharedInstance()
        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let v = change.newValue else { return }
            DispatchQueue.main.async { self?.show(volume: v) }
        }
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.playPause(); return .success }
        center.playCommand.addTarget { [weak self] _ in self?.playPause(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.playPause(); return .success }
    }

    private func show(volume: Float) {
        show(symbol: volume == 0 ? "speaker.slash.fill" : volume < 0.34 ? "speaker.wave.1.fill" : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill",
             level: volume)
    }

    func show(symbol: String, level: Float?) {
        hud = (symbol, level)
        hudWork?.cancel()
        let work = DispatchWorkItem { [weak self] in withAnimation(.easeOut(duration: 0.25)) { self?.hud = nil } }
        hudWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    /// Sets the iPhone's volume (the slider of a hidden system volume view: the only way an app may).
    private func setVolume(_ v: Float) {
        if volumeView.superview == nil, let w = PhoneWindow.current { w.addSubview(volumeView) }
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.value = max(0, min(1, v))
        slider.sendActions(for: .valueChanged)
    }

    func volumeStep(_ delta: Float) {
        mutedLevel = nil
        setVolume(AVAudioSession.sharedInstance().outputVolume + delta)
    }

    func toggleMute() {
        let now = AVAudioSession.sharedInstance().outputVolume
        if let m = mutedLevel { setVolume(m); mutedLevel = nil } else { mutedLevel = max(now, 0.1); setVolume(0) }
    }

    /// Plays or pauses the video or sound on the desktop: the one in the window in front, else any that plays.
    func playPause() {
        let model = DesktopModel.shared
        let script = """
        (() => {
          const media = Array.from(document.querySelectorAll('video, audio'));
          const playing = media.filter(m => !m.paused);
          if (playing.length) { playing.forEach(m => m.pause()); return 'paused'; }
          const m = media.find(m => m.currentTime > 0) || media[0];
          if (m) { m.play().catch(() => {}); return 'playing'; }
          return 'none';
        })()
        """
        let ordered = ([model.focused] + model.windows.reversed()).compactMap { $0?.webView }
        func attempt(_ i: Int) {
            guard i < ordered.count else { return }
            ordered[i].evaluateJavaScript(script) { [weak self] result, _ in
                let r = result as? String ?? "none"
                if r == "none" { attempt(i + 1); return }
                self?.show(symbol: r == "paused" ? "pause.fill" : "play.fill", level: nil)
            }
        }
        attempt(0)
    }
}

struct MediaHUDView: View {
    @ObservedObject var media = MediaControl.shared
    let size: CGSize
    var body: some View {
        if let hud = media.hud {
            VStack(spacing: 14) {
                Image(systemName: hud.symbol).font(.system(size: 44, weight: .medium)).frame(height: 54)
                if let level = hud.level {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.2))
                            Capsule().fill(Color.white).frame(width: g.size.width * CGFloat(level))
                        }
                    }
                    .frame(width: 150, height: 6)
                }
            }
            .padding(26)
            .frame(width: 200, height: 170)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .frame(width: size.width, height: size.height * 0.82, alignment: .bottom)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}
