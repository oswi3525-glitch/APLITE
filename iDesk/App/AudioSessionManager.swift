import AVFoundation
import UIKit
import os.log


// Diagnostics model types live in AudioDiagnostics.swift so they can be unit tested in isolation.


// MARK: - Manager

/// The **only** owner of `AVAudioSession` in this process.
///
/// Guest apps are loaded into APLite's process, so every audio source — guest apps, WKWebView media,
/// AVPlayer in Quick Look, speech synthesis and voice typing — shares one session. Before this class
/// existed, four different places changed that session independently: launch activated the default
/// (silent-switch-sensitive) category, Read Aloud set a category without activating it, Voice Typing
/// deactivated the whole session when it stopped, and nobody listened for interruptions or route
/// changes. Any of those left the desktop silent until the app was restarted.
///
/// This manager keeps a `.playback` baseline active for the whole lifetime of the app, temporarily
/// switches to `.playAndRecord` only while voice typing is listening, and restores playback
/// afterwards. It never creates a player or synthesises sound: it only manages the session.
final class AudioSessionManager: NSObject, ObservableObject {
    static let shared = AudioSessionManager()

    @Published private(set) var snapshot: AudioSnapshot?
    @Published private(set) var events: [AudioEvent] = []
    /// True while the system has an active interruption (call, Siri, other app's audio).
    @Published private(set) var isInterrupted = false
    /// Set once at launch. Guest apps share this process and may change the category themselves;
    /// when the last one closes we put the desktop's playback baseline back.
    var guestAppsActive: () -> Bool = { false }

    private var started = false
    private var recording = false
    private var observers: [NSObjectProtocol] = []
    private var log = AudioEventLog()
    private let osLog = OSLog(subsystem: "com.hieuk.aplite", category: "Audio")

    private override init() { super.init() }

    // MARK: Lifecycle

    /// Call once from `AppDelegate`. Safe to call again; the observers are installed only once.
    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] in self?.handleInterruption($0) })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] in self?.handleRouteChange($0) })
        observers.append(center.addObserver(forName: .GuestRuntimeWindowsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.note(.diagnostic, "Guest app windows changed")
            self?.refresh()
            if !(self?.guestAppsActive() ?? false) { self?.activatePlayback(reason: "last guest app closed") }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.note(.lifecycle, "App became active")
            self?.reactivateCurrentMode(reason: "app became active")
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            // Do NOT deactivate here: playback audio should be allowed to continue (e.g. during a
            // picture-in-picture style switch or while another APLite scene takes over).
            self?.note(.lifecycle, "App entered background")
            self?.refresh()
        })
        activatePlayback(reason: "launch")
        note(.diagnostic, "AudioSessionManager started")
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: Public API

    /// Ensures media (web pages, guest apps, Quick Look, speech) can play. Idempotent.
    func activatePlayback(reason: String = "manual") {
        let session = AVAudioSession.sharedInstance()
        do {
            if session.isActive, session.category == .playback, session.mode == .default {
                refresh()
                return
            }
            if session.isActive { try session.setActive(false, options: .notifyOthersOnDeactivation) }
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            note(.playback, "Playback session activated (\(reason))")
            refresh()
            NotificationCenter.default.post(name: .apliteAudioDidResume, object: self)
        } catch {
            note(.error, "Cannot activate playback session (\(reason)): \(error.localizedDescription)")
            refresh()
        }
    }

    /// Switches to a recording session. Voice Typing must pair this with `endRecording()`.
    func beginRecording(reason: String = "voice typing") {
        let session = AVAudioSession.sharedInstance()
        do {
            if session.isActive { try session.setActive(false, options: .notifyOthersOnDeactivation) }
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            recording = true
            note(.recording, "Recording session activated (\(reason))")
            refresh()
        } catch {
            note(.error, "Cannot activate recording session (\(reason)): \(error.localizedDescription)")
            refresh()
        }
    }

    /// Restores the playback baseline after recording. This is the fix for "everything went silent
    /// after I used voice typing": the session is never left deactivated.
    func endRecording() {
        guard recording else { return }
        recording = false
        activatePlayback(reason: "recording ended")
    }

    /// A human-readable report for Settings, DebugScript and crash diagnostics.
    func report(maxEvents: Int = 14) -> String {
        let snap = snapshot ?? currentSnapshot()
        let base = snap.report(preamble: String(localized: "APLite audio diagnostics"))
        let prefix = String(localized: "Interruption")
        let state = isInterrupted ? String(localized: "active") : String(localized: "none")
        let recent = log.events.suffix(max(0, maxEvents)).map(\.line).joined(separator: "\n")
        return """
        \(base)
        \(prefix): \(state)
        \(String(localized: "Recent events")):
        \(recent.isEmpty ? String(localized: "none") : recent)
        """
    }

    func copyReportToPasteboard() {
        UIPasteboard.general.string = report()
        note(.diagnostic, "Diagnostics copied to clipboard")
    }

    func clearEventLog() {
        log.clear()
        publishEvents()
    }

    // MARK: Notifications

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            isInterrupted = true
            note(.interruption, "Interruption began")
            refresh()
        case .ended:
            isInterrupted = false
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            let resume = options.contains(.shouldResume)
            note(.interruption, "Interruption ended (shouldResume=\(resume ? "yes" : "no"))")
            if resume { reactivateCurrentMode(reason: "interruption ended") } else { refresh() }
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        let info = notification.userInfo ?? [:]
        let reason = (info[AVAudioSessionRouteChangeReasonKey] as? UInt)
            .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            .map(Self.routeReasonName) ?? String(localized: "unknown")
        let previous = (info[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription)
        let from = previous.map { Self.ports($0.outputs).map(\.name).joined(separator: ", ") } ?? String(localized: "unknown")
        note(.route, "Route changed: \(reason) (was: \(from))")
        refresh()
        // Unplugging headphones or a display can leave the session inactive without an interruption.
        // Re-activate without overriding a guest app that deliberately changed the category.
        let session = AVAudioSession.sharedInstance()
        if !session.isActive, !recording, !isInterrupted {
            activatePlayback(reason: "route change")
        }
    }

    private func reactivateCurrentMode(reason: String) {
        if recording { beginRecording(reason: reason) } else { activatePlayback(reason: reason) }
    }

    // MARK: Internals

    private func currentSnapshot() -> AudioSnapshot {
        let s = AVAudioSession.sharedInstance()
        return AudioSnapshot(category: s.category.rawValue, mode: s.mode.rawValue,
                             options: Self.optionNames(s.categoryOptions), isActive: s.isActive,
                             outputVolume: s.outputVolume, sampleRate: s.sampleRate,
                             ioBufferDuration: s.ioBufferDuration,
                             outputs: Self.ports(s.currentRoute.outputs),
                             inputs: Self.ports(s.currentRoute.inputs),
                             timestamp: Date())
    }

    private func refresh() {
        let new = currentSnapshot()
        if let old = snapshot, old.category != new.category || old.isActive != new.isActive || old.routeDescription != new.routeDescription {
            note(.diagnostic, "Session now: \(new.category), active=\(new.isActive ? "yes" : "no"), output=\(new.routeDescription)")
        }
        snapshot = new
    }

    private func note(_ kind: AudioEventKind, _ message: String) {
        log.append(AudioEvent(kind: kind, message: message))
        publishEvents()
        os_log("[APLiteAudio] %{public}s", log: osLog, type: kind == .error ? .error : .info, message)
    }

    private func publishEvents() { events = log.events }

    private static func ports(_ descriptions: [AVAudioSessionPortDescription]) -> [AudioPortSummary] {
        descriptions.map(AudioPortSummary.init)
    }

    private static func optionNames(_ options: AVAudioSession.CategoryOptions) -> [String] {
        var names: [String] = []
        if options.contains(.mixWithOthers) { names.append("MixWithOthers") }
        if options.contains(.duckOthers) { names.append("DuckOthers") }
        if options.contains(.allowBluetooth) { names.append("AllowBluetooth") }
        if options.contains(.defaultToSpeaker) { names.append("DefaultToSpeaker") }
        if options.contains(.interruptSpokenAudioAndMixWithOthers) { names.append("InterruptSpokenAudioAndMixWithOthers") }
        if options.contains(.allowBluetoothA2DP) { names.append("AllowBluetoothA2DP") }
        if options.contains(.allowAirPlay) { names.append("AllowAirPlay") }
        if #available(iOS 14.5, *), options.contains(.overrideMutedMicrophoneInterruption) { names.append("OverrideMutedMicrophoneInterruption") }
        return names
    }

    private static func routeReasonName(_ reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .newDeviceAvailable: return String(localized: "new device available")
        case .oldDeviceUnavailable: return String(localized: "old device unavailable")
        case .categoryChange: return String(localized: "category changed")
        case .`override`: return String(localized: "override")
        case .wakeFromSleep: return String(localized: "woke from sleep")
        case .noSuitableRouteForCategory: return String(localized: "no suitable route for category")
        case .unknown: return String(localized: "unknown")
        @unknown default: return String(localized: "unknown")
        }
    }
}

extension Notification.Name {
    /// Posted whenever the audio session becomes active again (launch, interruption end, route change).
    static let apliteAudioDidResume = Notification.Name("APLiteAudioDidResume")
}
