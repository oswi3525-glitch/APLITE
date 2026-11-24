import GameController
import Combine
import QuartzCore
import UIKit
import os

/// A real mouse (USB or Bluetooth). Two ways in, and APLite draws its own pointer on the external display either way
/// (iOS shows no pointer there):
/// - GameController (`GCMouse`): raw motion, buttons and wheel, with nothing on the iPhone's screen. Preferred.
///   Whether iOS hands a mouse to an iPhone app this way depends on the device and the iOS version, so it is only
///   known by trying (the Mouse check screen counts what arrives).
/// - AssistiveTouch: iOS's own pointer on the iPhone's screen, which TrackpadView reads (hover, pointer touches,
///   wheel). The fallback; while GameController delivers, its events are ignored so nothing is handled twice.
///
/// Motion is accumulated on GameController's own high-priority handler queue and applied once per display frame.
/// This is what keeps a wireless mouse smooth: no per-event UI work, no main-run-loop batching, and no dependency on
/// the run loop mode (the display link uses `.common`, so it keeps running while scrolling or dragging a window).
final class MouseInput: ObservableObject {
    static let shared = MouseInput()
    var scrollSpeed: CGFloat = 12

    /// GameController callbacks must not share the main queue with the desktop: a mouse produces hundreds of
    /// events a second and the main queue delivers them in batches, which is felt as stutter.
    private static let handlerQueue = DispatchQueue.global(qos: .userInteractive)
    private static let latencyLog = OSLog(subsystem: "com.hieuk.aplite", category: "MouseLatency")

    enum Source { case none, gameController, assistiveTouch }

    @Published private(set) var mouseConnected = false
    @Published private(set) var mouseActive = false      // actually received mouse data
    @Published private(set) var source: Source = .none   // which path the mouse input arrives through
    @Published private(set) var keyboardConnected = false
    /// iOS reports at least one real mouse through GameController. While true the virtual touchpad stands aside.
    @Published private(set) var physicalMouseConnected = false

    /// The virtual touchpad must not receive touch/hover events while a real mouse drives the pointer.
    var suppressesVirtualTouchpad: Bool { physicalMouseConnected || source == .gameController }

    /// What has arrived through each path since launch, for the Mouse check screen (read on a timer, not published:
    /// a mouse sends hundreds of events a second).
    struct Counters {
        var miceFound = 0, connects = 0, disconnects = 0, withoutInput = 0
        var moves = 0, buttons = 0, rightButtons = 0, middleButtons = 0, scrolls = 0
        var pointerHover = 0, pointerPresses = 0, pointerRightPresses = 0, pointerScrolls = 0
        var lastMouseName = ""
    }
    private(set) var counters = Counters()

    /// One lock guards everything written from a GameController handler queue. UI-facing published properties are
    /// still only written on the main thread (inside `flushFrame` or the main-queue button handlers).
    private let state = NSLock()
    private var pendingDX: CGFloat = 0
    private var pendingDY: CGFloat = 0
    private var pendingScrollX: CGFloat = 0
    private var pendingScrollY: CGFloat = 0
    private var immediateRenderScheduled = false
    private var frameLink: CADisplayLink?

    private struct Sample {
        let received: CFTimeInterval
        var rendered: CFTimeInterval?
    }
    /// Last 240 move → render pairs, for the latency readout in Mouse check.
    private var samples: [Sample] = []
    /// Off in normal use: a mouse sends hundreds of events a second. The Mouse check screen turns it on to emit
    /// timestamped per-event lines into the unified log (never into APLite's on-disk log).
    var motionTraceEnabled = false

    /// Last GameController event; while recent, the AssistiveTouch path stands aside (see TrackpadView).
    private var lastEvent: CFTimeInterval = 0
    var recentlyActive: Bool {
        state.lock(); defer { state.unlock() }
        return CACurrentMediaTime() - lastEvent < 0.4
    }

    /// Mean time from a mouse move arriving to the cursor being rendered, in milliseconds.
    var averageLatencyMs: Double {
        state.lock(); let snapshot = samples; state.unlock()
        let rendered = snapshot.filter { $0.rendered != nil }
        guard !rendered.isEmpty else { return 0 }
        return rendered.reduce(0) { $0 + Double($1.rendered! - $1.received) * 1000 } / Double(rendered.count)
    }
    var latencySampleCount: Int {
        state.lock(); defer { state.unlock() }
        return samples.filter { $0.rendered != nil }.count
    }

    private var attached = Set<ObjectIdentifier>()

    /// Called by TrackpadView when the indirect pointer (mouse via AssistiveTouch) is active.
    func indirectPointerSeen() {
        guard !suppressesVirtualTouchpad else { return }
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
            mouse.handlerQueue = Self.handlerQueue
            self.attach(mouse, attempt: 0)
            self.refresh()
        }
        nc.addObserver(forName: .GCMouseDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            self.counters.disconnects += 1
            if let mouse = note.object as? GCMouse { self.attached.remove(ObjectIdentifier(mouse)) }
            self.refresh()   // re-enables the virtual touchpad when the last mouse goes away
        }
        nc.addObserver(forName: .GCMouseDidBecomeCurrent, object: nil, queue: .main) { [weak self] note in
            if let mouse = note.object as? GCMouse {
                mouse.handlerQueue = Self.handlerQueue
                self?.attach(mouse, attempt: 0)
            }
        }
        nc.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        nc.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        // Coming back to the foreground: GameController may hand over mice it did not report while in the background.
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            GCMouse.mice().forEach { self?.attach($0, attempt: 0) }
            self?.refresh()
        }

        // `.common` is essential: a link added for `.default` stops while the run loop is in tracking mode, i.e.
        // exactly while the user is scrolling or dragging a window — the moments a mouse must stay responsive.
        let link = CADisplayLink(target: MouseFrameTick(self), selector: #selector(MouseFrameTick.tick))
        link.add(to: .main, forMode: .common)
        frameLink = link

        let mice = GCMouse.mice()
        counters.miceFound = mice.count
        mice.forEach { attach($0, attempt: 0) }
        refresh()
    }

    private func refresh() {
        let mice = GCMouse.mice()
        counters.miceFound = mice.count
        // Cover every connected mouse, not just `current`: two mice can be attached at once and both must use the
        // high-priority queue. The handlers are installed per device, so neither can hijack the other's deltas.
        for mouse in mice { mouse.handlerQueue = Self.handlerQueue }
        GCMouse.current?.handlerQueue = Self.handlerQueue
        physicalMouseConnected = !mice.isEmpty
        if !mice.isEmpty { mouseConnected = true }
        else if source != .assistiveTouch { mouseConnected = false }
        keyboardConnected = GCKeyboard.coalesced != nil
    }

    private func touch() {
        state.lock(); lastEvent = CACurrentMediaTime(); state.unlock()
        if source != .gameController { source = .gameController }
        if !mouseConnected { mouseConnected = true }
        if !mouseActive { mouseActive = true }
    }

    /// Called on the GameController queue. Accumulates only — no UIKit, no published state, no main-queue hop.
    private func accumulateMotion(dx: Float, dy: Float) {
        let k = InputSettings.pointerSpeed / CGFloat(InputSettings.defaultPointer)
        state.lock()
        pendingDX += CGFloat(dx) * k
        pendingDY += CGFloat(-dy) * k
        counters.moves += 1
        lastEvent = CACurrentMediaTime()
        samples.append(Sample(received: lastEvent, rendered: nil))
        if samples.count > 240 { samples.removeFirst(samples.count - 240) }
        // The first move after an idle moment renders at once instead of waiting up to a full frame; later
        // moves in the same frame are coalesced by the display link. This keeps mean latency below one frame.
        let scheduleImmediate = !immediateRenderScheduled
        if scheduleImmediate { immediateRenderScheduled = true }
        state.unlock()
        if scheduleImmediate { DispatchQueue.main.async { [weak self] in self?.flushFrame() } }
    }

    private func accumulateScroll(x: Float, y: Float, speed: CGFloat) {
        let k = speed * InputSettings.scrollDirection
        state.lock()
        pendingScrollX += CGFloat(x) * k
        pendingScrollY += CGFloat(-y) * k
        counters.scrolls += 1
        lastEvent = CACurrentMediaTime()
        let scheduleImmediate = !immediateRenderScheduled
        if scheduleImmediate { immediateRenderScheduled = true }
        state.unlock()
        if scheduleImmediate { DispatchQueue.main.async { [weak self] in self?.flushFrame() } }
    }

    /// One cursor update per display frame. All the expensive work in `DesktopModel.moveCursor` (hit testing,
    // window dragging, hover) therefore runs at most 60 times a second instead of once per hardware event.
    @objc private func flushFrame() {
        state.lock()
        let dx = pendingDX, dy = pendingDY, sx = pendingScrollX, sy = pendingScrollY
        pendingDX = 0; pendingDY = 0; pendingScrollX = 0; pendingScrollY = 0
        immediateRenderScheduled = false
        let now = CACurrentMediaTime()
        var justRendered: [Sample] = []
        for i in samples.indices where samples[i].rendered == nil {
            samples[i].rendered = now
            justRendered.append(samples[i])
        }
        let trace = motionTraceEnabled
        state.unlock()

        if trace {
            for s in justRendered {
                os_log("move received=%.6f rendered=%.6f latency=%.3fms",
                       log: Self.latencyLog, type: .debug,
                       s.received, s.rendered ?? now, Double((s.rendered ?? now) - s.received) * 1000)
            }
        }

        guard dx != 0 || dy != 0 || sx != 0 || sy != 0 else { return }
        touch()
        let model = DesktopModel.shared
        if dx != 0 || dy != 0 { model.moveCursor(dx: dx, dy: dy) }
        if sx != 0 || sy != 0 { model.scroll(dx: sx, dy: sy) }
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
        mouse.handlerQueue = Self.handlerQueue
        attached.insert(ObjectIdentifier(mouse))
        counters.lastMouseName = mouse.vendorName ?? ""
        let model = DesktopModel.shared

        input.mouseMovedHandler = { [weak self] _, dx, dy in
            self?.accumulateMotion(dx: dx, dy: dy)
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
            self?.accumulateScroll(x: x, y: y, speed: speed)
        }
    }
}

/// Weak proxy: a CADisplayLink retains its target, and MouseInput is a singleton that lives for the process.
private final class MouseFrameTick: NSObject {
    weak var input: MouseInput?
    init(_ input: MouseInput) { self.input = input }
    @objc func tick() { input?.flushFrame() }
}
