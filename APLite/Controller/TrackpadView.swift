import UIKit
import SwiftUI
import Combine

/// Turns the iPhone screen into a trackpad.
/// - one-finger drag: move the pointer
/// - tap: click (two quick taps: double click)
/// - two-finger tap: right click
/// - hold still ~0.25 s, then drag, or tap and then touch and drag: press and drag (move a window by its title bar,
///   resize from an edge/corner, select text)
/// - two-finger drag: scroll; flick and it keeps going, slowing down (momentum, as on a laptop trackpad)
/// - three fingers, like the iPhone's home-bar gestures: swipe up = Recent apps (the app switcher), down = Home,
///   left / right = next / previous app, tap = Back
/// - four fingers: swipe left / right = next / previous workspace, tap = app menu
///
/// Fallback for a real mouse when GCMouse delivers nothing:
/// the AssistiveTouch pointer (hover, left/right buttons, wheel) over the trackpad.
///
/// Mirror mode (`mirrorMode`): the trackpad shows a live mirror of the desktop, and wherever you touch or
/// click, the desktop pointer goes to that exact spot. Meant for a mouse via AssistiveTouch: iOS draws that
/// pointer on the iPhone screen only, so pointing at the mirror means pointing at the desktop.
final class TrackpadView: UIView {
    private let model = DesktopModel.shared

    private var lastPoint: CGPoint?
    private var startPoint: CGPoint = .zero
    private var startTime: TimeInterval = 0
    private var moved = false
    private var dragging = false
    private var maxTouches = 0
    private var twoFingerLast: CGPoint?
    private var twoFingerTravel: CGFloat = 0
    private var holdTimer: Timer?
    private var lastTapEnd: TimeInterval = 0      // a tap just ended: touching again and dragging presses and drags
    private var tapDragArmed = false
    // Momentum scrolling: the fingers' speed when they lift, then a slowly decaying scroll.
    private var scrollVelocity: CGPoint = .zero
    private var lastScrollTime: TimeInterval = 0
    private var scrollGain: CGFloat = 1
    private var momentum: CADisplayLink?
    private var momentumLast: CFTimeInterval = 0
    private var multiStart: CGPoint?        // centroid when three or more fingers came down
    private var multiHandled = false        // the swipe already did its action
    /// Beta builds only: hold four fingers still to open the survey tool. A four-finger tap keeps
    /// opening the app menu, so no existing gesture changes.
    private var surveyHoldTimer: Timer?
    private let tapFeedback = UIImpactFeedbackGenerator(style: .light)
    private let holdFeedback = UIImpactFeedbackGenerator(style: .medium)

    // Real pointer (indirect pointer)
    private var hoverLast: CGPoint?
    private var pointerLast: CGPoint?
    private var pointerPressed = false   // left button held (the right button only opens the menu)
    private var scrollLast: CGPoint = .zero

    // Mirror mode
    var mirrorMode = false {
        didSet {
            guard mirrorMode != oldValue else { return }
            resetGesture()
            updateMirror()
        }
    }
    private var mirror: UIView?
    private var mirrorIsLive = false
    private var mirrorTimer: Timer?
    private var snapshotLink: CADisplayLink?
    private var stackWatch: AnyCancellable?
    private var absStart: CGPoint = .zero
    private var absPressed = false      // pressed on the desktop (dragging)
    private var absHandled = false      // this touch was already handled (right button), no click

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Trackpad")
        accessibilityHint = String(localized: "Drag one finger to move the pointer, tap to click, two-finger tap to right-click, two-finger drag to scroll, three-finger swipe up for recent apps")
        accessibilityTraits = .allowsDirectInteraction

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(onHover(_:)))
        addGestureRecognizer(hover)

        let wheel = UIPanGestureRecognizer(target: self, action: #selector(onWheel(_:)))
        wheel.allowedScrollTypesMask = .all
        wheel.allowedTouchTypes = []          // only mouse wheel / scroll input, not fingers
        addGestureRecognizer(wheel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        mirrorTimer?.invalidate()
        snapshotLink?.invalidate()
        // This link targets `self` directly, so it must be broken here or the view leaks after a
        // flick (the other links use a weak proxy).
        momentum?.invalidate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutMirror()
    }

    // MARK: Mirror mode

    /// The part of the trackpad that shows the desktop (keeps the external display's aspect ratio).
    private var desktopRect: CGRect {
        let s = model.screenSize
        guard s.width > 0, s.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let k = min(bounds.width / s.width, bounds.height / s.height)
        let size = CGSize(width: s.width * k, height: s.height * k)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private func desktopPoint(_ p: CGPoint) -> CGPoint {
        let r = desktopRect, s = model.screenSize
        return CGPoint(x: min(max((p.x - r.minX) / r.width * s.width, 0), s.width - 1),
                       y: min(max((p.y - r.minY) / r.height * s.height, 0), s.height - 1))
    }

    /// Moves the desktop pointer to the matching point (via moveCursor so window dragging / hover still work).
    private func jump(to p: CGPoint) {
        let d = desktopPoint(p), c = model.cursor.position
        model.moveCursor(dx: d.x - c.x, dy: d.y - c.y)
    }

    private func updateMirror() {
        mirrorTimer?.invalidate()
        mirrorTimer = nil
        removeMirror()
        stackWatch = nil
        guard mirrorMode else { return }
        // The external display may be connected (or removed) later: check again periodically.
        mirrorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshMirror()
        }
        // An iOS app opened or closed: switch between the live mirror and pictures at once.
        stackWatch = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshMirror() }
        }
        refreshMirror()
    }

    /// The mirror is a live portal of the desktop while only web pages and APLite's own windows are open. iOS
    /// apps are themselves portals of windows on the iPhone screen inside the desktop, and a portal of them in
    /// turn (desktop → iPhone → desktop) breaks the display: the app window turned black, now and then or for
    /// good, and was not raised when clicked. With an app open, the mirror shows pictures of the desktop instead
    /// (taken by the system, a dozen a second), which leave the display alone.
    private func refreshMirror() {
        guard let source = ExternalSceneDelegate.desktopView, source.window != nil else {
            removeMirror()
            return
        }
        let live = !model.windows.contains { $0.guestWindow != nil }
        guard mirror == nil || mirrorIsLive != live else { return }
        removeMirror()
        let container = UIView()
        container.isUserInteractionEnabled = false
        container.clipsToBounds = true
        if live {
            guard let portal = Portal.make(of: source, hidesSource: false) else { return }
            portal.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(portal)
        } else {
            let link = CADisplayLink(target: MirrorTick(self), selector: #selector(MirrorTick.tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 12)
            link.add(to: .main, forMode: .common)
            snapshotLink = link
        }
        mirrorIsLive = live
        mirror = container
        insertSubview(container, at: 0)
        layoutMirror()
        if !live { updateSnapshot() }
    }

    private func removeMirror() {
        snapshotLink?.invalidate()
        snapshotLink = nil
        mirror?.removeFromSuperview()
        mirror = nil
    }

    /// A new picture of the desktop in place of the last one.
    fileprivate func updateSnapshot() {
        guard let mirror, let source = ExternalSceneDelegate.desktopView, source.window != nil,
              let picture = source.snapshotView(afterScreenUpdates: false) else { return }
        picture.frame = mirror.bounds
        picture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mirror.subviews.forEach { $0.removeFromSuperview() }
        mirror.addSubview(picture)
    }

    private func layoutMirror() {
        guard let mirror, let source = ExternalSceneDelegate.desktopView else { return }
        let r = desktopRect
        let size = source.bounds.size
        guard size.width > 0 else { return }
        let k = r.width / size.width
        mirror.transform = .identity
        mirror.bounds = CGRect(origin: .zero, size: size)
        mirror.subviews.forEach { $0.frame = mirror.bounds }
        mirror.center = CGPoint(x: r.midX, y: r.midY)
        mirror.transform = CGAffineTransform(scaleX: k, y: k)
    }

    private func resetGesture() {
        stopMomentum()
        holdTimer?.invalidate()
        surveyHoldTimer?.invalidate()
        if dragging { model.mouseUp(); dragging = false }
        if absPressed { model.physicalRelease(); absPressed = false }
        if pointerPressed { model.physicalRelease(); pointerPressed = false }
        lastPoint = nil
        pointerLast = nil
        twoFingerLast = nil
        maxTouches = 0
        absHandled = false
        multiStart = nil
        multiHandled = false
    }

    private func absoluteBegan(_ touches: Set<UITouch>, _ event: UIEvent?) {
        let active = activeTouches(event, includePointer: true)
        beginGestureIfNeeded(touches)
        maxTouches = max(maxTouches, active.count)
        if active.count == 1, let t = active.first {
            if t.type == .indirectPointer {
                MouseInput.shared.indirectPointerSeen()
                MouseInput.shared.count(event?.buttonMask.contains(.secondary) == true ? .rightPress : .press)
                // The same mouse is already arriving through GameController: do not click twice.
                if MouseInput.shared.recentlyActive { absHandled = true; maxTouches = 1; moved = true; return }
            }
            let p = t.location(in: self)
            absStart = p
            jump(to: p)
            if event?.buttonMask.contains(.secondary) == true {
                absHandled = true
                tapFeedback.impactOccurred()
                model.rightClick()
            }
        } else if active.count >= 2 {
            if absPressed { model.physicalRelease(); absPressed = false }
            twoFingerLast = centroid(active)
        }
    }

    private func absoluteMoved(_ event: UIEvent?) {
        let active = activeTouches(event, includePointer: true)
        if active.count >= 2 {
            // The mirror is smaller than the desktop: scroll by the distance the fingers travel on the desktop.
            twoFingerScroll(active, gain: model.screenSize.width / max(desktopRect.width, 1))
            return
        }
        guard maxTouches == 1, !absHandled, let t = active.first else { return }
        let p = t.location(in: self)
        if !moved, hypot(p.x - absStart.x, p.y - absStart.y) > 6 {
            // A real drag: press at the start point, then follow the finger/mouse (a slight wobble is still a click).
            moved = true
            model.physicalPress()
            absPressed = true
        }
        if moved { jump(to: p) }
    }

    private func absoluteEnded(_ touches: Set<UITouch>, _ event: UIEvent?, allowClick: Bool) {
        let remaining = activeTouches(event, includePointer: true).filter { !touches.contains($0) }
        guard remaining.isEmpty else { return }
        if absPressed {
            model.physicalRelease()
            absPressed = false
        } else if allowClick, !moved, !absHandled {
            if maxTouches == 1 {
                tapFeedback.impactOccurred()
                model.click()
            } else if maxTouches == 2, isQuick(touches) {
                tapFeedback.impactOccurred()
                model.rightClick()
            }
        }
        twoFingerLast = nil
        maxTouches = 0
        absHandled = false
    }

    // MARK: Real pointer

    @objc private func onHover(_ g: UIHoverGestureRecognizer) {
        let p = g.location(in: self)
        switch g.state {
        case .began: hoverLast = p
        case .changed:
            MouseInput.shared.indirectPointerSeen()
            MouseInput.shared.count(.hover)
            if MouseInput.shared.recentlyActive { hoverLast = p; break }   // GameController moves the pointer
            if mirrorMode { jump(to: p); break }
            if let l = hoverLast, !MouseInput.shared.recentlyActive {
                model.moveCursor(dx: (p.x - l.x) * 2, dy: (p.y - l.y) * 2)
            }
            hoverLast = p
        default: hoverLast = nil
        }
    }

    @objc private func onWheel(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        if g.state == .began { scrollLast = .zero; MouseInput.shared.count(.scroll) }
        if !MouseInput.shared.recentlyActive {
            let k = 2 * InputSettings.scrollDirection
            model.scroll(dx: -(t.x - scrollLast.x) * k, dy: -(t.y - scrollLast.y) * k)
        }
        scrollLast = t
        if g.state == .ended || g.state == .cancelled { scrollLast = .zero }
    }

    private func pointerTouch(_ touches: Set<UITouch>) -> UITouch? {
        touches.first { $0.type == .indirectPointer }
    }

    // MARK: Touches

    /// Fingers (and the pointer, if `includePointer`) still on the trackpad.
    private func activeTouches(_ event: UIEvent?, includePointer: Bool = false) -> [UITouch] {
        (event?.allTouches ?? []).filter {
            $0.phase != .ended && $0.phase != .cancelled && (includePointer || $0.type != .indirectPointer)
        }
    }

    /// Starts a new gesture (first finger down).
    private func beginGestureIfNeeded(_ touches: Set<UITouch>) {
        guard maxTouches == 0, let t = touches.first else { return }
        startTime = t.timestamp
        moved = false
        absHandled = false
        twoFingerTravel = 0
    }

    private func isQuick(_ touches: Set<UITouch>) -> Bool {
        (touches.first.map { $0.timestamp - startTime } ?? 1) < 0.35
    }

    /// Two-finger drag = "natural" scrolling (push up, the page goes up). `gain`: iPhone points to desktop points.
    private func twoFingerScroll(_ active: [UITouch], gain speed: CGFloat) {
        let gain = speed * InputSettings.scrollDirection
        let c = centroid(active)
        let now = active.first?.timestamp ?? CACurrentMediaTime()
        if let l = twoFingerLast {
            twoFingerTravel += hypot(c.x - l.x, c.y - l.y)
            model.scroll(dx: -(c.x - l.x) * gain, dy: -(c.y - l.y) * gain)
            let dt = now - lastScrollTime
            if dt > 0.001 {
                let v = CGPoint(x: (c.x - l.x) / dt, y: (c.y - l.y) / dt)
                scrollVelocity = CGPoint(x: scrollVelocity.x * 0.3 + v.x * 0.7, y: scrollVelocity.y * 0.3 + v.y * 0.7)
            }
        }
        lastScrollTime = now
        scrollGain = gain
        twoFingerLast = c
        if twoFingerTravel > 10 { moved = true }
    }

    /// After a flick: keep scrolling at the fingers' speed, slowing down until it stops.
    private func startMomentum() {
        let speed = hypot(scrollVelocity.x, scrollVelocity.y)
        guard speed > 180, CACurrentMediaTime() - lastScrollTime < 0.08 else { scrollVelocity = .zero; return }
        stopMomentum()
        momentumLast = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(momentumTick(_:)))
        link.add(to: .main, forMode: .common)
        momentum = link
    }

    @objc private func momentumTick(_ link: CADisplayLink) {
        let now = link.timestamp, dt = min(0.05, max(0, now - momentumLast))
        momentumLast = now
        model.scroll(dx: -scrollVelocity.x * dt * scrollGain, dy: -scrollVelocity.y * dt * scrollGain)
        let decay = CGFloat(pow(0.94, dt * 60))
        scrollVelocity = CGPoint(x: scrollVelocity.x * decay, y: scrollVelocity.y * decay)
        if hypot(scrollVelocity.x, scrollVelocity.y) < 25 { stopMomentum() }
    }

    private func stopMomentum() {
        momentum?.invalidate()
        momentum = nil
        scrollVelocity = .zero
    }

    private func centroid(_ touches: [UITouch]) -> CGPoint {
        let pts = touches.map { $0.location(in: self) }
        return CGPoint(x: pts.map(\.x).reduce(0, +) / CGFloat(pts.count),
                       y: pts.map(\.y).reduce(0, +) / CGFloat(pts.count))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if mirrorMode { return absoluteBegan(touches, event) }
        if let t = pointerTouch(touches) {
            // A real mouse button went down (AssistiveTouch pointer)
            MouseInput.shared.indirectPointerSeen()
            MouseInput.shared.count(event?.buttonMask.contains(.secondary) == true ? .rightPress : .press)
            guard !MouseInput.shared.recentlyActive else { return }
            pointerLast = t.location(in: self)
            if event?.buttonMask.contains(.secondary) == true {
                model.rightClick()
            } else {
                pointerPressed = true
                model.physicalPress()
            }
            return
        }

        let active = activeTouches(event)
        stopMomentum()          // a finger down stops a momentum scroll, as on a trackpad
        beginGestureIfNeeded(touches)
        maxTouches = max(maxTouches, active.count)

        if active.count == 1, let t = active.first {
            let p = t.location(in: self)
            lastPoint = p
            startPoint = p
            tapDragArmed = t.timestamp - lastTapEnd < 0.3
            holdTimer?.invalidate()
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                guard let self, !self.moved, self.maxTouches == 1 else { return }
                self.dragging = true
                self.holdFeedback.impactOccurred()
                self.model.mouseDown()
            }
        } else if active.count >= 3 {
            holdTimer?.invalidate()
            if dragging { model.mouseUp(); dragging = false }
            lastPoint = nil
            twoFingerLast = nil
            multiStart = centroid(active)
            if APLite.isBeta, active.count >= 4 {
                surveyHoldTimer?.invalidate()
                surveyHoldTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
                    guard let self, self.maxTouches >= 4, !self.multiHandled else { return }
                    self.multiHandled = true
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    NotificationCenter.default.post(name: .apliteStartBetaSurvey, object: nil)
                }
            }
        } else if active.count >= 2 {
            holdTimer?.invalidate()
            lastPoint = nil
            twoFingerLast = centroid(active)
        }
    }

    /// Three or four fingers moving together: one action per swipe, once they have travelled far enough.
    private func multiFingerMoved(_ active: [UITouch]) {
        guard active.count >= 3, !multiHandled else { return }
        let c = centroid(active)
        guard let start = multiStart else { multiStart = c; return }
        let dx = c.x - start.x, dy = c.y - start.y
        guard max(abs(dx), abs(dy)) > 45 else { return }
        surveyHoldTimer?.invalidate()
        multiHandled = true
        moved = true
        holdFeedback.impactOccurred()
        let horizontal = abs(dx) > abs(dy)
        if maxTouches >= 4 {
            if horizontal { model.switchWorkspace(by: dx < 0 ? 1 : -1) }
            else if dy < 0 { model.toggleRecents() } else { model.goHome() }
        } else if horizontal {
            model.switchApp(forward: dx < 0)
        } else if dy < 0 {
            model.toggleRecents()
        } else {
            model.goHome()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if mirrorMode { return absoluteMoved(event) }
        if let t = pointerTouch(touches) {
            let p = t.location(in: self)
            if let l = pointerLast, !MouseInput.shared.recentlyActive {
                model.moveCursor(dx: (p.x - l.x) * 2, dy: (p.y - l.y) * 2)
            }
            pointerLast = p
            return
        }

        let active = activeTouches(event)

        if maxTouches >= 3 {
            multiFingerMoved(active)
            return
        }
        if active.count >= 2 {
            twoFingerScroll(active, gain: InputSettings.scrollSpeed)
            return
        }

        guard let t = active.first, let l = lastPoint else { return }
        let p = t.location(in: self)
        // Tap, then touch and drag: press where the pointer is before it starts moving.
        if tapDragArmed, !dragging, maxTouches == 1, hypot(p.x - startPoint.x, p.y - startPoint.y) > 8 {
            tapDragArmed = false
            holdTimer?.invalidate()
            dragging = true
            model.mouseDown()
        }
        // Until then the pointer stays put, so the press lands where the tap was.
        if tapDragArmed, !dragging { return }
        if hypot(p.x - startPoint.x, p.y - startPoint.y) > 6 { moved = true }
        let dx = p.x - l.x, dy = p.y - l.y
        let speed = hypot(dx, dy)
        let gain = InputSettings.pointerSpeed * (1 + min(speed, 40) / 16)   // acceleration: fast swipes go further
        model.moveCursor(dx: dx * gain, dy: dy * gain)
        lastPoint = p
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, event, allowClick: true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, event, allowClick: false)
    }

    private func finish(_ touches: Set<UITouch>, _ event: UIEvent?, allowClick: Bool) {
        surveyHoldTimer?.invalidate()
        if mirrorMode { return absoluteEnded(touches, event, allowClick: allowClick) }
        if pointerTouch(touches) != nil {
            if pointerPressed { model.physicalRelease() }
            pointerPressed = false
            pointerLast = nil
            return
        }

        let remaining = activeTouches(event).filter { !touches.contains($0) }
        if remaining.isEmpty {
            holdTimer?.invalidate()
            if dragging {
                model.mouseUp()
                dragging = false
            } else if maxTouches >= 3 {
                // A tap with three fingers = Back, with four = app menu.
                if allowClick, !multiHandled, !moved, isQuick(touches) {
                    tapFeedback.impactOccurred()
                    if maxTouches >= 4 { model.toggleLauncher() } else { model.goBack() }
                }
            } else if maxTouches == 2, moved, allowClick {
                startMomentum()
            } else if allowClick, !moved, isQuick(touches), !MouseInput.shared.recentlyActive {
                if maxTouches == 1 {
                    tapFeedback.impactOccurred()
                    model.click()
                    lastTapEnd = touches.first?.timestamp ?? 0
                } else if maxTouches == 2 {
                    tapFeedback.impactOccurred()
                    model.rightClick()
                }
            }
            tapDragArmed = false
            lastPoint = nil
            twoFingerLast = nil
            maxTouches = 0
            multiStart = nil
            multiHandled = false
        } else if maxTouches >= 3 {
            return       // lifting some of the fingers of a three-finger gesture: not a pointer move
        } else if remaining.count == 1 {
            lastPoint = remaining[0].location(in: self)
            twoFingerLast = nil
        }
    }
}

struct TrackpadSurface: UIViewRepresentable {
    var mirrorMode = false
    func makeUIView(context: Context) -> TrackpadView { TrackpadView() }
    func updateUIView(_ uiView: TrackpadView, context: Context) { uiView.mirrorMode = mirrorMode }
}

/// Calls the trackpad on each display frame without the display link keeping it alive.
private final class MirrorTick: NSObject {
    weak var view: TrackpadView?
    init(_ view: TrackpadView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) {
        guard let view else { link.invalidate(); return }
        view.updateSnapshot()
    }
}
