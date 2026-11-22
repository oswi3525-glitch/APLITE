import UIKit
import SwiftUI

/// Hidden text view that receives typing (the iPhone keyboard, or a hardware keyboard) through the iOS input methods,
/// so Vietnamese Telex / VNI, Japanese, Chinese… work, and mirrors it onto the desktop.
///
/// Input methods compose by rewriting what was just typed ("viet" + "j" becomes "việt"), so the view keeps the current
/// word: after each change, what differs from what the desktop already got is sent as deletions followed by the new
/// characters. The word is forgotten at a space or Enter, or when the pointer clicks somewhere (another field).
/// Shortcuts and navigation keys (arrows, Esc, Tab, ⌘ / Ctrl / Alt combinations) go to PhoneWindow instead.
final class KeyCaptureView: UITextView, UITextViewDelegate {
    static weak var current: KeyCaptureView?
    var onInsert: (String) -> Void = { _ in }
    var onDelete: () -> Void = {}
    var onEnter: () -> Void = {}
    /// The text the desktop has received for the current word (what the view holds).
    private var sent = ""
    private let noKeyboard = UIView(frame: .zero)
    private var resetObserver: NSObjectProtocol?
    static let resetNotification = Notification.Name("iDeskTypingReset")

    /// Whether the iPhone's on-screen keyboard shows ("live typing"). Hidden, a hardware keyboard still types here.
    var showsKeyboard = false {
        didSet {
            guard showsKeyboard != oldValue else { return }
            inputView = showsKeyboard ? nil : noKeyboard
            if isFirstResponder { reloadInputViews() }
        }
    }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 1, height: 1), textContainer: nil)
        delegate = self
        inputView = noKeyboard
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        inlinePredictionType = .no
        backgroundColor = .clear
        textColor = .clear
        tintColor = .clear
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        Self.current = self
        resetObserver = NotificationCenter.default.addObserver(forName: Self.resetNotification, object: nil,
                                                               queue: .main) { [weak self] _ in self?.forgetWord() }
    }

    deinit {
        if let resetObserver { NotificationCenter.default.removeObserver(resetObserver) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Starts a new word without touching what the desktop already has.
    func forgetWord() {
        guard markedTextRange == nil else { return }
        sent = ""
        text = ""
    }

    func textViewDidChange(_ textView: UITextView) {
        let now = text ?? ""
        let old = Array(sent), new = Array(now)
        var same = 0
        while same < old.count, same < new.count, old[same] == new[same] { same += 1 }
        for _ in same..<old.count { onDelete() }
        let added = String(new[same...])
        let lines = added.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if i > 0 { onEnter() }
            if !line.isEmpty { onInsert(line) }
        }
        sent = now
        // A finished word (or line): start afresh, so the next one cannot rewrite text in another field.
        if markedTextRange == nil, lines.count > 1 || now.hasSuffix(" ") || now.count > 64 { forgetWord() }
    }

    /// Delete with nothing left in the current word: delete on the desktop.
    override func deleteBackward() {
        if (text ?? "").isEmpty, markedTextRange == nil { onDelete() } else { super.deleteBackward() }
    }

    // MARK: Keys that are not text

    private static let navigationKeys: Set<UIKeyboardHIDUsage> = [
        .keyboardLeftArrow, .keyboardRightArrow, .keyboardUpArrow, .keyboardDownArrow, .keyboardEscape, .keyboardTab,
        .keyboardDeleteForward, .keyboardPageUp, .keyboardPageDown, .keyboardHome, .keyboardEnd, .keyboardPrintScreen,
        .keyboardLeftGUI, .keyboardRightGUI, .keyboardLeftAlt, .keyboardRightAlt, .keyboardLeftControl, .keyboardRightControl,
    ]

    private func split(_ presses: Set<UIPress>) -> (shortcuts: Set<UIPress>, text: Set<UIPress>) {
        var shortcuts = Set<UIPress>(), text = Set<UIPress>()
        for press in presses {
            guard let key = press.key else { text.insert(press); continue }
            let f = key.modifierFlags
            // While composing (marked text), arrows and Tab belong to the input method.
            if markedTextRange == nil && (Self.navigationKeys.contains(key.keyCode)
                || f.contains(.command) || f.contains(.control) || f.contains(.alternate)) {
                shortcuts.insert(press)
            } else {
                text.insert(press)
            }
        }
        return (shortcuts, text)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let (shortcuts, text) = split(presses)
        if !shortcuts.isEmpty { PhoneWindow.current?.pressesBegan(shortcuts, with: event) }
        if !text.isEmpty { super.pressesBegan(text, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let (shortcuts, text) = split(presses)
        if !shortcuts.isEmpty { PhoneWindow.current?.pressesEnded(shortcuts, with: event) }
        if !text.isEmpty { super.pressesEnded(text, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let (shortcuts, text) = split(presses)
        if !shortcuts.isEmpty { PhoneWindow.current?.pressesCancelled(shortcuts, with: event) }
        if !text.isEmpty { super.pressesCancelled(text, with: event) }
    }

    // No copy / paste / selection menus on the hidden view: ⌘C / ⌘V act on the desktop.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
}

struct KeyCapture: UIViewRepresentable {
    /// Typing goes to the desktop (a display is connected and no field on the iPhone is being edited).
    let isActive: Bool
    /// The iPhone's keyboard is shown ("live typing").
    let showsKeyboard: Bool
    let model: DesktopModel

    func makeUIView(context: Context) -> KeyCaptureView {
        let v = KeyCaptureView()
        v.onInsert = { text in model.typeText(text) }
        v.onDelete = { model.backspace() }
        v.onEnter = { model.pressEnter() }
        return v
    }

    func updateUIView(_ v: KeyCaptureView, context: Context) {
        let active = isActive, keyboard = showsKeyboard
        DispatchQueue.main.async {
            v.showsKeyboard = keyboard
            if active, !v.isFirstResponder { v.becomeFirstResponder() }
            if !active, v.isFirstResponder { v.resignFirstResponder() }
        }
    }
}

// MARK: - Hardware keyboard (Bluetooth / USB)

/// The iPhone screen's window. It handles desktop shortcuts and navigation keys, which KeyCaptureView (the first
/// responder while typing goes to the desktop) passes on to it.
final class PhoneWindow: UIWindow {
    enum Mode {
        case all        // handle every key (no KeyCaptureView)
        case special    // text goes through KeyCaptureView (and the input methods), shortcuts and special keys here
        case off        // typing into a field on the iPhone: leave keys alone
    }

    static weak var current: PhoneWindow?
    static var mode: Mode = .all

    private let model = DesktopModel.shared
    private var repeatTimer: Timer?
    private var repeatKey: UIKeyboardHIDUsage?
    /// The ⌘ key went down and nothing else has been pressed since: releasing it opens the app menu.
    private var winKeyAlone = false

    private static func isWinKey(_ code: UIKeyboardHIDUsage?) -> Bool {
        code == .keyboardLeftGUI || code == .keyboardRightGUI
    }

    private static func isAltKey(_ code: UIKeyboardHIDUsage?) -> Bool {
        code == .keyboardLeftAlt || code == .keyboardRightAlt
    }

    override var canBecomeFirstResponder: Bool { true }

    /// Takes the keyboard back (a guest app may have grabbed it).
    func claimKeyboard() {
        DispatchQueue.main.async {
            switch Self.mode {
            case .special:
                if let capture = KeyCaptureView.current, !capture.isFirstResponder { capture.becomeFirstResponder() }
            case .all:
                if !self.isFirstResponder { self.becomeFirstResponder() }
            case .off:
                break
            }
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        winKeyAlone = presses.count == 1 && Self.isWinKey(presses.first?.key?.keyCode)
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key, Self.mode != .off, handle(key) else { unhandled.insert(press); continue }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.key?.keyCode == repeatKey }) { stopRepeat() }
        let codes = presses.map { $0.key?.keyCode }
        // Releasing the modifier of ⌥ + Tab / ⌘ + Tab switches to the selected window.
        if codes.contains(where: { Self.isWinKey($0) || Self.isAltKey($0) }) { model.commitSwitcher() }
        if winKeyAlone, Self.mode != .off, codes.contains(where: { Self.isWinKey($0) }) { model.toggleLauncher() }
        winKeyAlone = false
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        stopRepeat()
        super.pressesCancelled(presses, with: event)
    }

    /// Returns true if the key was handled.
    private func handle(_ key: UIKey) -> Bool {
        // Locked, or the screen saver: a key only wakes the desktop.
        if model.isLocked || model.showScreenSaver { model.noteInput(); return true }
        let flags = key.modifierFlags
        let shift = flags.contains(.shift)
        let chars = key.charactersIgnoringModifiers.lowercased()

        if Self.performShortcut(chars: chars, keyCode: key.keyCode, flags: flags) { return true }

        switch key.keyCode {
        case .keyboardPrintScreen:
            model.takeScreenshot(); return true
        case .keyboardVolumeUp: MediaControl.shared.volumeStep(0.0625); return true
        case .keyboardVolumeDown: MediaControl.shared.volumeStep(-0.0625); return true
        case .keyboardMute: MediaControl.shared.toggleMute(); return true
        case .keyboardF8: MediaControl.shared.playPause(); return true
        case .keyboardEscape:
            model.escape(); return true
        case .keyboardLeftArrow: special(key, "ArrowLeft", 37, shift); return true
        case .keyboardRightArrow: special(key, "ArrowRight", 39, shift); return true
        case .keyboardUpArrow: special(key, "ArrowUp", 38, shift); return true
        case .keyboardDownArrow: special(key, "ArrowDown", 40, shift); return true
        case .keyboardPageUp: model.sendKey("PageUp", 33, shift); return true
        case .keyboardPageDown: model.sendKey("PageDown", 34, shift); return true
        case .keyboardHome: model.sendKey("Home", 36, shift); return true
        case .keyboardEnd: model.sendKey("End", 35, shift); return true
        case .keyboardDeleteForward: special(key, "Delete", 46, shift); return true
        case .keyboardTab: model.sendKey("Tab", 9, shift); return true
        default: break
        }

        // From here on, text keys: in "live typing" mode KeyCaptureView handles them.
        guard Self.mode == .all else { return false }
        switch key.keyCode {
        case .keyboardReturnOrEnter, .keypadEnter:
            model.pressEnter(); return true
        case .keyboardDeleteOrBackspace:
            model.backspace()
            startRepeat(key) { [weak self] in self?.model.backspace() }
            return true
        default:
            let text = key.characters
            guard !text.isEmpty, !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
            model.typeText(text)
            return true
        }
    }

    /// The desktop's shortcuts with ⌘, Ctrl or ⌥ (⌘T, ⌘C, ⌘ + arrows…), for a hardware keyboard and for the keyboard
    /// of a laptop showing the desktop in its browser (RemoteDisplay). Returns true if the keys were a shortcut.
    static func performShortcut(chars: String, keyCode: UIKeyboardHIDUsage, flags: UIKeyModifierFlags) -> Bool {
        let model = DesktopModel.shared
        let command = flags.contains(.command) || flags.contains(.control)
        let shift = flags.contains(.shift)
        // Desktop-style shortcuts
        if command {
            switch chars {
            case "t": if shift { model.reopenClosed() } else { model.newTabOrWindow() }; return true
            case "n": model.newBrowserWindow(); return true
            case "l": model.focusAddressBar(); return true
            case "y": model.openPage(.history); return true                     // as in Safari and Chrome
            case "h": model.minimizeFocused(); return true                      // hide, as on a Mac
            case "q":
                // ⌃⌘Q locks the desktop, as on a Mac; ⌘Q closes the whole window, every tab.
                if flags.contains(.control) && flags.contains(.command) { model.lockDesktop(force: true) }
                else if let w = model.focused { model.close(w) }
                return true
            case "`": model.cycleWindows(); return true
            case "w": model.closeFocused(); return true
            case "r": model.reload(); return true
            case "[": model.goBack(); return true
            case "]": model.goForward(); return true
            case "a": model.selectAll(); return true
            case "c": model.copySelection(); return true
            case "x": model.cutSelection(); return true
            case "v": if shift { model.toggleClipboard() } else { model.paste() }; return true
            case " ": if flags.contains(.control) && flags.contains(.command) { model.toggleEmoji() } else { model.toggleSpotlight() }; return true
            case "d": model.toggleShowDesktop(); return true
            case "m": model.minimizeFocused(); return true
            case "/": model.showShortcuts.toggle(); return true
            case "f": model.findInPage(); return true
            case "g": model.findAgain(backwards: shift); return true
            case "=", "+": model.zoom(1); return true
            case "-": model.zoom(-1); return true
            case "0": model.zoom(0); return true
            default: break
            }
            // ⌘ + Tab: Recent apps (stays open); Ctrl+Tab: switch like ⌥ + Tab.
            if keyCode == .keyboardTab {
                if flags.contains(.command) { model.showRecents() } else { model.nextTab(backwards: shift) }
                return true
            }
            // Screenshots as on a Mac: ⌘⇧3 the whole screen, ⌘⇧4 (or ⌘⇧S) an area or a window.
            if shift, keyCode == .keyboard3 { model.takeScreenshot(); return true }
            if shift, keyCode == .keyboard5 { ScreenRecorder.shared.toggle(); return true }
            if shift, [.keyboardS, .keyboard4].contains(keyCode) { model.startAreaCapture(); return true }
            // ⌘1…9: a tab of the browser window.
            if !flags.contains(.control), let n = Int(chars), (1...9).contains(n) { model.selectTab(number: n); return true }
            // ⌘ + Ctrl + ← / →: previous / next workspace (with Shift: take the window along); ⌘ + Ctrl+1…4.
            if flags.contains(.command) && flags.contains(.control) {
                switch keyCode {
                case .keyboardLeftArrow: if shift { model.moveFocusedToWorkspace(by: -1) } else { model.switchWorkspace(by: -1) }; return true
                case .keyboardRightArrow: if shift { model.moveFocusedToWorkspace(by: 1) } else { model.switchWorkspace(by: 1) }; return true
                default:
                    if let n = Int(chars), (1...DesktopModel.workspaceCount).contains(n) { model.setWorkspace(n - 1); return true }
                }
            }
            // ⌘ + arrows arrange the window, as on a computer; Ctrl + ← / → go back / forward.
            let win = flags.contains(.command)
            switch keyCode {
            case .keyboardLeftArrow: if win { model.snapFocused(.left) } else { model.goBack() }; return true
            case .keyboardRightArrow: if win { model.snapFocused(.right) } else { model.goForward() }; return true
            case .keyboardUpArrow where win: model.snapFocused(.up); return true
            case .keyboardDownArrow where win: model.snapFocused(.down); return true
            default: return false
            }
        }
        if flags.contains(.alternate) {
            switch keyCode {
            case .keyboardTab: model.cycleWindows(); return true
            case .keyboardSpacebar: model.toggleSpotlight(); return true   // when ⌘ + Space switches the keyboard language
            case .keyboardLeftArrow: model.goBack(); return true        // as in browsers
            case .keyboardRightArrow: model.goForward(); return true
            default: break
            }
        }

        return false
    }

    private func special(_ key: UIKey, _ name: String, _ code: Int, _ shift: Bool) {
        model.sendKey(name, code, shift)
        startRepeat(key) { [weak self] in self?.model.sendKey(name, code, shift) }
    }

    /// Holding a key (delete, arrows) repeats it like on a computer.
    private func startRepeat(_ key: UIKey, _ action: @escaping () -> Void) {
        stopRepeat()
        repeatKey = key.keyCode
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in action() }
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        repeatKey = nil
    }
}
