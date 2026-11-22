import GameController
import Combine
import QuartzCore
import UIKit

/// A real mouse (USB or Bluetooth). Two ways in, and iDesk draws its own pointer on the external display either way
/// (iOS shows no pointer there):
/// - GameController (`GCMouse`): raw motion, buttons and wheel, with nothing on the iPhone's screen. Preferred.
///   Whether iOS hands a mouse to an iPhone app this way depends on the device and the iOS version, so it is only
///   known by trying (the Mouse check screen counts what arrives).
/// - AssistiveTouch: iOS's own pointer on the iPhone's screen, which TrackpadView reads (hover, pointer touches,
///   wheel). The fallback; while GameController delivers, its events are ignored so nothing is handled twice.
final class MouseInput: ObservableObject {
    static let shared = MouseInput()
    var scrollSpeed: CGFloat = 12

    enum Source { case none, gameController, assistiveTouch }

    @Published private(set) var mouseConnected = false
    @Published private(set) var mouseActive = false      // actually received mouse data
    @Published private(set) var source: Source = .none   // which path the mouse input arrives through
    @Published private(set) var keyboardConnected = false

    /// What has arrived through each path since launch, for the Mouse check screen (read on a timer, not published:
    /// a mouse sends hundreds of events a second).
    struct Counters {
        var miceFound = 0, connects = 0, disconnects = 0, withoutInput = 0
        var moves = 0, buttons = 0, rightButtons = 0, middleButtons = 0, scrolls = 0
        var pointerHover = 0, pointerPresses = 0, pointerRightPresses = 0, pointerScrolls = 0
        var lastMouseName = ""
    }
    private(set) var counters = Counters()

    /// Last GameController event; while recent, the AssistiveTouch path stands aside (see TrackpadView).
    private(set) var lastEvent: CFTimeInterval = 0
    var recentlyActive: Bool { CACurrentMediaTime() - lastEvent < 0.4 }

    private var attached = Set<ObjectIdentifier>()

    /// Called by TrackpadView when the indirect pointer (mouse via AssistiveTouch) is active.
    func indirectPointerSeen() {
        if source != .gameController {
            source = .assistiveTouch
            mouseConnected = true
            mouseActive = true
        }
    }

    /// TrackpadView's AssistiveTouch events, counted for the Mouse check screen.
    enum PointerEvent { case hover, press, rightPress, scroll }
    func count(_ event: PointerEvent) {
        switch event {
        case .hover: counters.pointerHover += 1
        case .press: counters.pointerPresses += 1
        case .rightPress: counters.pointerRightPresses += 1
        case .scroll: counters.pointerScrolls += 1
        }
    }

    func start() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let self, let mouse = note.object as? GCMouse else { return }
            self.counters.connects += 1
            self.attach(mouse, attempt: 0)
            self.refresh()
        }
        nc.addObserver(forName: .GCMouseDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            self.counters.disconnects += 1
            if let mouse = note.object as? GCMouse { self.attached.remove(ObjectIdentifier(mouse)) }
            self.refresh()
        }
        nc.addObserver(forName: .GCMouseDidBecomeCurrent, object: nil, queue: .main) { [weak self] note in
            if let mouse = note.object as? GCMouse { self?.attach(mouse, attempt: 0) }
        }
        nc.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        nc.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        // Coming back to the foreground: GameController may hand over mice it did not report while in the background.
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            GCMouse.mice().forEach { self?.attach($0, attempt: 0) }
            self?.refresh()
        }
        let mice = GCMouse.mice()
        counters.miceFound = mice.count
        mice.forEach { attach($0, attempt: 0) }
        refresh()
    }

    private func refresh() {
        let mice = GCMouse.mice()
        counters.miceFound = mice.count
        if !mice.isEmpty { mouseConnected = true }
        else if source != .assistiveTouch { mouseConnected = false }
        keyboardConnected = GCKeyboard.coalesced != nil
    }

    private func touch() {
        lastEvent = CACurrentMediaTime()
        if source != .gameController { source = .gameController }
        if !mouseConnected { mouseConnected = true }
        if !mouseActive { mouseActive = true }
    }

    /// Sets up the handlers. A freshly connected mouse may not have its input profile yet: try again a few times.
    private func attach(_ mouse: GCMouse, attempt: Int) {
        guard !attached.contains(ObjectIdentifier(mouse)) else { return }
        guard let input = mouse.mouseInput else {
            if attempt == 0 { counters.withoutInput += 1 }
            if attempt < 6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 * Double(attempt + 1)) { [weak self] in
                    self?.attach(mouse, attempt: attempt + 1)
                }
            }
            return
        }
        attached.insert(ObjectIdentifier(mouse))
        counters.lastMouseName = mouse.vendorName ?? ""
        let model = DesktopModel.shared

        input.mouseMovedHandler = { [weak self] _, dx, dy in
            DispatchQueue.main.async {
                self?.touch()
                self?.counters.moves += 1
                // GameController's Y axis points up, the screen's points down.
                let k = InputSettings.pointerSpeed / CGFloat(InputSettings.defaultPointer)
                model.moveCursor(dx: CGFloat(dx) * k, dy: CGFloat(-dy) * k)
            }
        }
        input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
            DispatchQueue.main.async {
                self?.touch()
                if pressed { self?.counters.buttons += 1 }
                if pressed { model.physicalPress() } else { model.physicalRelease() }
            }
        }
        input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            DispatchQueue.main.async {
                self?.touch()
                if pressed { self?.counters.rightButtons += 1; model.rightClick() }
            }
        }
        input.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            DispatchQueue.main.async {
                self?.touch()
                if pressed { self?.counters.middleButtons += 1; model.middleClick() }
            }
        }
        input.scroll.valueChangedHandler = { [weak self] _, x, y in
            let speed = (self?.scrollSpeed ?? 12) * InputSettings.scrollSpeed / CGFloat(InputSettings.defaultScroll)
            DispatchQueue.main.async {
                self?.touch()
                self?.counters.scrolls += 1
                let k = speed * InputSettings.scrollDirection
                model.scroll(dx: CGFloat(x) * k, dy: CGFloat(-y) * k)
            }
        }
    }
}
