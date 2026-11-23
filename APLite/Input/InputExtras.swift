import SwiftUI
import Speech
import AVFoundation
import GameController
import WebKit

// MARK: - Voice typing

/// The microphone button on the iPhone: speak, and the words go where the desktop is typing (in the iPhone's
/// language: Vietnamese on a Vietnamese iPhone). Tap again to stop; what was said is typed when it ends.
final class VoiceTyping: ObservableObject {
    static let shared = VoiceTyping()
    /// A call/Siri stops the audio session. Stop cleanly instead of leaving "Listening…" with a dead engine.
    private init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw), type == .began else { return }
                self?.stop(send: false)
            }
    }
    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    @Published private(set) var isListening = false
    @Published private(set) var heard = ""
    @Published var problem: String?

    private let engine = AVAudioEngine()
    private var interruptionObserver: NSObjectProtocol?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer? { SFSpeechRecognizer(locale: Locale(identifier: Locale.preferredLanguages.first ?? "vi-VN")) }

    func toggle() { isListening ? stop(send: true) : start() }

    private func start() {
        problem = nil
        SFSpeechRecognizer.requestAuthorization { status in
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    guard status == .authorized, granted else {
                        self.problem = String(localized: "Allow Microphone and Speech Recognition for APLite in the iPhone's Settings.")
                        return
                    }
                    self.begin()
                }
            }
        }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else {
            problem = String(localized: "Voice typing is not available for this language right now."); return
        }
        // The shared manager switches the category and, crucially, restores playback when we stop.
        // Setting the category here directly used to leave the whole desktop silent after voice typing.
        guard AudioSessionManager.shared.beginRecording() else {
            problem = String(localized: "The microphone could not be started. Close other apps using it and try again.")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.request = request
        heard = ""
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }
        engine.prepare()
        do { try engine.start() } catch {
            // Never leave the shared session in .playAndRecord: that ducks/mutes the whole desktop.
            input.removeTap(onBus: 0)
            self.request = nil
            task = nil
            AudioSessionManager.shared.endRecording()
            problem = error.localizedDescription
            return
        }
        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result { self.heard = result.bestTranscription.formattedString }
                if result?.isFinal == true || error != nil, self.isListening { self.stop(send: true) }
            }
        }
    }

    func stop(send: Bool) {
        guard isListening else { return }
        isListening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        AudioSessionManager.shared.endRecording()
        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        heard = ""
        if send, !text.isEmpty { DesktopModel.shared.typeText(text + " ") }
    }
}

/// Over the iPhone's controls while listening: what has been heard so far.
struct VoiceTypingBanner: View {
    @ObservedObject var voice = VoiceTyping.shared
    var body: some View {
        if voice.isListening || voice.problem != nil {
            HStack(spacing: 10) {
                Image(systemName: voice.isListening ? "waveform" : "exclamationmark.triangle")
                    .symbolEffect(.variableColor.iterative, isActive: voice.isListening)
                    .foregroundStyle(voice.isListening ? APLiteColors.red : APLiteColors.orange)
                Text(verbatim: voice.isListening ? (voice.heard.isEmpty ? String(localized: "Listening… tap the microphone again to type it") : voice.heard)
                                                 : (voice.problem ?? ""))
                    .font(.callout).lineLimit(3)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 14)
            .onTapGesture { voice.problem = nil }
        }
    }
}

// MARK: - Emoji

enum EmojiPanel {
    static let all: [String] = Array("😀😃😄😁😆😅😂🤣😊😇🙂🙃😉😌😍🥰😘😗😋😛😜🤪😝🤗🤭🤫🤔🤐😐😑😶😏😒🙄😬😮‍💨🤥😴😷🤒🤕🤢🤮🥵🥶🥴😵🤯🤠🥳😎🤓🧐😕😟🙁😮😯😲😳🥺😦😧😨😰😥😢😭😱😖😣😞😓😩😫🥱😤😡😠🤬😈💀💩🤡👻👽🤖😺❤️🧡💛💚💙💜🖤🤍🤎💔❣️💕💞💓💗💖💘💝👍👎👌✌️🤞🤟🤘🤙👈👉👆👇☝️👋🤚🖐️✋👏🙌👐🤲🙏💪🔥✨⭐🌟💯✅❌⚠️❓❗🎉🎊🎁🎂☕🍜🍕🍔🍟🍣🍺🥂⚽🏀🎮🎧📱💻⌨️🖥️📷📌📎✏️📝📅⏰🚀✈️🚗🏠🌈☀️🌙⛅🌧️❄️🌸🌹🍀🐶🐱🐼🦊🐸").map(String.init)
    static let columns = 12
    static let cell: CGFloat = 40
    static let padding: CGFloat = 10
    static let header: CGFloat = 34
}

extension DesktopModel {
    func toggleEmoji() {
        guard isExternalConnected else { return }
        let open = !showEmoji
        closePanels()
        emojiIndex = 0
        showEmoji = open
    }

    var emojiRect: CGRect {
        let rows = CGFloat((EmojiPanel.all.count + EmojiPanel.columns - 1) / EmojiPanel.columns)
        let w = EmojiPanel.padding * 2 + CGFloat(EmojiPanel.columns) * EmojiPanel.cell
        let h = EmojiPanel.padding * 2 + EmojiPanel.header + rows * EmojiPanel.cell
        let p = cursor.position
        return CGRect(x: min(max(8, p.x - w / 2), screenSize.width - w - 8), y: max(8, min(p.y + 20, taskbarTop - h - 8)), width: w, height: h)
    }

    func emojiCellRect(_ i: Int, in r: CGRect) -> CGRect {
        CGRect(x: r.minX + EmojiPanel.padding + CGFloat(i % EmojiPanel.columns) * EmojiPanel.cell,
               y: r.minY + EmojiPanel.padding + EmojiPanel.header + CGFloat(i / EmojiPanel.columns) * EmojiPanel.cell,
               width: EmojiPanel.cell, height: EmojiPanel.cell)
    }

    func moveEmojiSelection(_ key: String) {
        let n = EmojiPanel.all.count, c = EmojiPanel.columns
        switch key {
        case "ArrowLeft": emojiIndex = max(0, emojiIndex - 1)
        case "ArrowRight": emojiIndex = min(n - 1, emojiIndex + 1)
        case "ArrowUp": emojiIndex = max(0, emojiIndex - c)
        case "ArrowDown": emojiIndex = min(n - 1, emojiIndex + c)
        default: break
        }
    }

    func insertEmoji(_ i: Int? = nil) {
        let e = EmojiPanel.all[i ?? emojiIndex]
        showEmoji = false
        DispatchQueue.main.async { [weak self] in self?.typeText(e) }
    }

    func clickEmoji(at p: CGPoint) {
        let r = emojiRect
        if let i = EmojiPanel.all.indices.first(where: { emojiCellRect($0, in: r).contains(p) }) { insertEmoji(i); return }
        if !r.contains(p) { showEmoji = false }
    }
}

struct EmojiPanelView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var cursor: CursorModel

    var body: some View {
        let r = model.emojiRect
        ZStack(alignment: .topLeading) {
            Text("Emoji · arrows and Enter, or click").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .offset(x: EmojiPanel.padding + 4, y: EmojiPanel.padding + 6)
            ForEach(EmojiPanel.all.indices, id: \.self) { i in
                let t = model.emojiCellRect(i, in: r)
                Text(verbatim: EmojiPanel.all[i]).font(.system(size: 24))
                    .frame(width: t.width, height: t.height)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(i == model.emojiIndex ? Color.accentColor.opacity(0.55) : t.contains(cursor.position) ? Color.white.opacity(0.14) : .clear))
                    .offset(x: t.minX - r.minX, y: t.minY - r.minY)
            }
        }
        .frame(width: r.width, height: r.height, alignment: .topLeading)
        .floatingPanel(cornerRadius: 14, shadow: 18)
        .offset(x: r.minX, y: r.minY)
    }
}

// MARK: - Text replacement

/// Settings → Typing → Text replacement: a short code typed on the desktop ("@@") becomes a phrase (an e-mail
/// address, a greeting) when followed by a space, Enter or punctuation.
enum TextReplacements {
    private static let key = "iDesk.textReplacements"
    static var all: [(short: String, phrase: String)] {
        get { (UserDefaults.standard.array(forKey: key) as? [[String]] ?? []).compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil } }
        set { UserDefaults.standard.set(newValue.map { [$0.short, $0.phrase] }, forKey: key) }
    }

    static func add(_ short: String, _ phrase: String) {
        let s = short.trimmingCharacters(in: .whitespaces), p = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !p.isEmpty, !s.contains(" ") else { return }
        all = all.filter { $0.short != s } + [(s, p)]
    }

    static func remove(_ short: String) { all = all.filter { $0.short != short } }

    /// What has been typed since the typing target last changed (kept short).
    static var typed = ""

    /// Called with each piece typed. When it ends a word that is a code, returns the code's length (to delete)
    /// and the phrase to type in its place.
    static func check(_ s: String) -> (delete: Int, phrase: String)? {
        defer { if typed.count > 64 { typed = String(typed.suffix(64)) } }
        guard s.count == 1, let c = s.first, c == " " || c == "\n" || ".,;:!?".contains(c) else {
            typed += s
            return nil
        }
        let word = typed.split(whereSeparator: { $0 == " " || $0 == "\n" }).last.map(String.init) ?? ""
        typed += s
        guard !word.isEmpty, let r = all.first(where: { $0.short == word }) else { return nil }
        typed = ""
        return (word.count, r.phrase)
    }
}

// MARK: - Game controller

/// A game controller (Xbox, PlayStation, MFi). In a game (an iOS app, or a web page that reads the controller)
/// the game gets it; elsewhere it drives the desktop: left stick moves the pointer, right stick scrolls, A clicks,
/// B goes back, X right-clicks, Menu opens the app menu, Options opens Spotlight.
final class ControllerInput {
    static let shared = ControllerInput()
    private var timer: Timer?
    private var pressed: Set<String> = []
    /// Windows whose page asked for the controller (navigator.getGamepads): a web game.
    static var gamePages = Set<ObjectIdentifier>()

    func start() {
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            if let c = n.object as? GCController {
                DesktopModel.shared.showToast(String(localized: "\(c.vendorName ?? String(localized: "Game controller")) connected"))
            }
            self?.update()
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in self?.update() }
        update()
    }

    /// The controller reports each change (a button, a stick): buttons act at once; the pointer and scrolling need
    /// a steady movement only while a stick is held off-centre, so the 60 Hz timer runs just then (nothing runs
    /// while the controller sits still).
    private func update() {
        for c in GCController.controllers() {
            c.extendedGamepad?.valueChangedHandler = { [weak self] pad, _ in self?.changed(pad) }
        }
        if GCController.controllers().isEmpty { stopMoving() }
    }

    /// Whether the window in front is a game that should get the controller itself.
    private var gameInFront: Bool {
        let model = DesktopModel.shared
        guard let w = model.focused, w.isShown else { return false }
        if w.guestWindow != nil { return true }
        if let web = w.webView { return Self.gamePages.contains(ObjectIdentifier(web)) }
        return false
    }

    private var drives: Bool { DesktopModel.shared.isExternalConnected && !gameInFront }

    private func changed(_ pad: GCExtendedGamepad) {
        guard drives else { stopMoving(); return }
        let model = DesktopModel.shared
        edge("a", pad.buttonA.isPressed) { model.click() }
        edge("b", pad.buttonB.isPressed) { model.goBack() }
        edge("x", pad.buttonX.isPressed) { model.rightClick() }
        edge("menu", pad.buttonMenu.isPressed) { model.toggleLauncher() }
        edge("options", pad.buttonOptions?.isPressed ?? false) { model.toggleSpotlight() }
        if Self.sticksMoved(pad), timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self, weak pad] _ in
                guard let self, let pad else { self?.stopMoving(); return }
                self.move(pad)
            }
        }
    }

    private static func sticksMoved(_ pad: GCExtendedGamepad) -> Bool {
        abs(pad.leftThumbstick.xAxis.value) > 0.12 || abs(pad.leftThumbstick.yAxis.value) > 0.12
            || abs(pad.rightThumbstick.xAxis.value) > 0.15 || abs(pad.rightThumbstick.yAxis.value) > 0.15
    }

    private func move(_ pad: GCExtendedGamepad) {
        guard drives, Self.sticksMoved(pad) else { stopMoving(); return }
        let model = DesktopModel.shared
        let lx = CGFloat(pad.leftThumbstick.xAxis.value), ly = CGFloat(pad.leftThumbstick.yAxis.value)
        if abs(lx) > 0.12 || abs(ly) > 0.12 {
            let speed: CGFloat = 18
            model.moveCursor(dx: lx * abs(lx) * speed, dy: -ly * abs(ly) * speed)
        }
        let rx = CGFloat(pad.rightThumbstick.xAxis.value), ry = CGFloat(pad.rightThumbstick.yAxis.value)
        if abs(rx) > 0.15 || abs(ry) > 0.15 { model.scroll(dx: rx * 22, dy: -ry * 22) }
    }

    private func stopMoving() { timer?.invalidate(); timer = nil }

    private func edge(_ name: String, _ down: Bool, _ action: () -> Void) {
        if down, !pressed.contains(name) { pressed.insert(name); action() }
        if !down { pressed.remove(name) }
    }

    /// Added to every tab: tells APLite when the page reads the controller (a web game).
    static var pageScript: WKUserScript { WKUserScript(source: gamepadsSource, injectionTime: .atDocumentStart, forMainFrameOnly: false) }
    static let messageName = "ideskGamepad"

    private static let gamepadsSource = """
    (() => {
      const orig = navigator.getGamepads && navigator.getGamepads.bind(navigator);
      if (!orig) return;
      let told = false;
      navigator.getGamepads = function () {
        if (!told) { told = true; try { window.webkit.messageHandlers.ideskGamepad.postMessage(1); } catch (_) {} }
        return orig();
      };
    })();
    """
}

/// The page reads the controller: from now on the controller is the game's while this tab is in front.
final class GamepadBridge: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let web = message.webView else { return }
        // Identifiers were never removed when a tab closed. Bound the set and drop stale ones in
        // one go; an old WKWebView identifier can never become valid again.
        if ControllerInput.gamePages.count >= 100 { ControllerInput.gamePages.removeAll() }
        ControllerInput.gamePages.insert(ObjectIdentifier(web))
    }
}
