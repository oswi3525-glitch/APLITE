import AVFoundation
import Combine
import CoreMedia
import QuartzCore
import UIKit

/// Produces the spectrum frames shown by the Dynamic Island. Analysis runs on a utility queue; only the ≤30 Hz
/// publication of the result touches the main thread. Web media already exposes an FFT (Web Audio's AnalyserNode)
/// and is ingested as bands; local Quick Look media is analysed here from PCM with an Accelerate FFT.
final class AudioSpectrumProvider: ObservableObject {
    static let shared = AudioSpectrumProvider()
    static let bandCount = SpectrumAnalyzer.bandCount

    /// Used while the pill is collapsed: a cheap, fixed wave. No analysis work per frame.
    static let calmLevels: [Float] = [0.10, 0.16, 0.26, 0.20, 0.32, 0.18, 0.24, 0.14, 0.20, 0.11, 0.16, 0.08]

    @Published private(set) var levels: [Float] = AudioSpectrumProvider.calmLevels

    private let analyzer = SpectrumAnalyzer()
    private let analysisQueue = DispatchQueue(label: "com.hieuk.aplite.spectrum", qos: .utility)
    private let lock = NSLock()
    private var pending: [(time: TimeInterval, bands: [Float])] = []
    private var webLevels = Array(repeating: Float(0), count: AudioSpectrumProvider.bandCount)
    private var reader: AVAssetReader?
    private weak var player: AVPlayer?
    private var analysisURL: URL?
    private var ticker: CADisplayLink?
    private var lastPublish: CFTimeInterval = 0
    private var published: [Float] = AudioSpectrumProvider.calmLevels
    private var expanded = false
    private var suspended = false

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.suspend()
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resume()
        }
    }

    func setExpanded(_ value: Bool) {
        guard expanded != value else { return }
        expanded = value
        if value { startTicker() } else { stopTicker(); publish(Self.calmLevels) }
    }

    /// Bands already normalised to 0…1 by Web Audio's AnalyserNode.
    func ingest(webBands: [Float]) {
        var normalised = Array(repeating: Float(0), count: AudioSpectrumProvider.bandCount)
        for (index, value) in webBands.prefix(AudioSpectrumProvider.bandCount).enumerated() {
            normalised[index] = min(1, max(0, value))
        }
        lock.lock(); webLevels = normalised; lock.unlock()
    }

    func startFileAnalysis(url: URL, player: AVPlayer) {
        stopFileAnalysis()
        analysisURL = url
        self.player = player
        guard let asset = player.currentItem?.asset as? AVURLAsset,
              let track = asset.tracks(withMediaType: .audio).first,
              let newReader = try? AVAssetReader(asset: asset) else { return }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ] as [String: Any])
        guard newReader.canAdd(output) else { return }
        newReader.add(output)
        guard newReader.startReading() else { return }
        reader = newReader
        lock.lock(); pending.removeAll(); lock.unlock()
        if !suspended { startTicker() }
        analysisQueue.async { [weak self] in self?.readPCM(output: output, reader: newReader) }
    }

    func stopFileAnalysis() {
        reader?.cancelReading()
        reader = nil
        player = nil
        analysisURL = nil
        lock.lock(); pending.removeAll(); lock.unlock()
        stopTicker()
        publish(Self.calmLevels)
    }

    func suspend() {
        suspended = true
        stopTicker()
        reader?.cancelReading()
        reader = nil
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        if expanded { startTicker() }
        if let url = analysisURL, let player { startFileAnalysis(url: url, player: player) }
    }

    // MARK: Internals

    private func startTicker() {
        guard ticker == nil, !suspended else { return }
        let link = CADisplayLink(target: SpectrumTick(self), selector: #selector(SpectrumTick.tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        ticker = link
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func publish(_ next: [Float]) {
        guard next != published else { return }
        published = next
        levels = next
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        guard now - lastPublish >= 1 / 30 else { return }
        lastPublish = now

        guard expanded else {
            publish(Self.calmLevels)
            return
        }

        lock.lock()
        let web = webLevels
        webLevels = Array(repeating: 0, count: AudioSpectrumProvider.bandCount)
        var chosen: [Float]?
        if let player {
            let t = player.currentTime().seconds
            for entry in pending where entry.time <= t + 0.02 { chosen = entry.bands }
            pending.removeAll { $0.time < t - 3 }
        }
        lock.unlock()
        publish(chosen ?? web)
    }

    private func readPCM(output: AVAssetReaderTrackOutput, reader: AVAssetReader) {
        var leftover: [Float] = []
        while reader.status == .reading, let buffer = output.copyNextSampleBuffer() {
            var blockBuffer: CMBlockBuffer?
            var list = AudioBufferList()
            let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                buffer,
                bufferListSizeNeededOut: nil,
                bufferListOut: &list,
                bufferListSize: MemoryLayout<AudioBufferList>.size,
                blockBufferAllocator: nil,
                blockBufferMemoryAllocator: nil,
                flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                blockBufferOut: &blockBuffer)
            guard status == noErr, let blockBuffer else { continue }
            var pointer: UnsafeMutablePointer<Int8>?
            var byteLength = 0
            guard CMBlockBufferGetDataPointer(blockBuffer, 0, nil, &byteLength, &pointer) == noErr,
                  let pointer, byteLength > 0 else { continue }
            let count = byteLength / MemoryLayout<Float>.size
            let samples = Array(UnsafeBufferPointer(start: pointer.bindMemory(to: Float.self, capacity: count),
                                                    count: count))
            leftover.append(contentsOf: samples)
            let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
            while leftover.count >= SpectrumAnalyzer.fftSize {
                let window = Array(leftover.prefix(SpectrumAnalyzer.fftSize))
                leftover.removeFirst(SpectrumAnalyzer.fftSize)
                let bands = analyzer.bands(from: window)
                lock.lock()
                pending.append((timestamp, bands))
                if pending.count > 1200 { pending.removeFirst(pending.count - 1200) }
                lock.unlock()
            }
        }
    }
}

private final class SpectrumTick: NSObject {
    weak var provider: AudioSpectrumProvider?
    init(_ provider: AudioSpectrumProvider) { self.provider = provider }
    @objc func tick() { provider?.tick() }
}
