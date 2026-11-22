import UIKit
import SwiftUI

/// Preview mode: shows a scaled-down desktop on the iPhone screen, controlled by touching it directly.
/// Used without an external display (Simulator, or a quick test of an IPA app).
/// Enabled with the `-iDeskPreview` launch argument; add `-iDeskInstall <path.ipa> [more.ipa…]` to install and open
/// apps,
/// or `-iDeskOpen <url>` to open a web page.
final class PreviewController: UIViewController {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-iDeskPreview") }

    private let model = DesktopModel.shared
    private let desktopSize = CGSize(width: 786, height: 1500)
    private lazy var host = UIHostingController(rootView: DesktopView(model: model))
    private var lastPan: CGPoint = .zero

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        model.screenSize = desktopSize

        host.overrideUserInterfaceStyle = .dark
        addChild(host)
        host.view.layer.anchorPoint = .zero
        host.view.bounds = CGRect(origin: .zero, size: desktopSize)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        ExternalSceneDelegate.desktopView = host.view     // what screenshots capture, as on a real display

        // A transparent shield over the desktop: real touches stop here and go through DesktopModel,
        // exactly like with an external display. The desktop itself cannot have interaction disabled: UIKit ignores
        // actions (row selection, buttons) in a guest app when any superview has interaction disabled.
        let shield = UIView(frame: view.bounds)
        shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(shield)
        shield.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
        pan.maximumNumberOfTouches = 1
        shield.addGestureRecognizer(pan)
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(scrolled))
        scroll.minimumNumberOfTouches = 2
        shield.addGestureRecognizer(scroll)
        // Touch and hold = right click (context menus).
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held))
        hold.minimumPressDuration = 0.6
        pan.require(toFail: hold)
        shield.addGestureRecognizer(hold)

        model.externalConnected()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaLayoutGuide.layoutFrame
        let s = min(safe.width / desktopSize.width, safe.height / desktopSize.height)
        host.view.transform = CGAffineTransform(scaleX: s, y: s)
        host.view.layer.position = safe.origin
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The error report of the last run (shown on the iPhone, which preview mode replaces): into the log.
        if let notice = model.notice { NSLog("[iDesk] %@", notice) }
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-iDeskOpen"), i + 1 < args.count {
            model.openWindow(args[i + 1])
        }
        // Every path after "-iDeskInstall" up to the next option; each app that installs is opened.
        guard let i = args.firstIndex(of: "-iDeskInstall") else { return }
        let ipas = args[(i + 1)...].prefix { !$0.hasPrefix("-") }.map { URL(fileURLWithPath: $0) }
        GuestStore.shared.install(ipas: ipas) { [model] results in
            NSLog("[iDesk] %@", GuestStore.summary(of: results))
            let apps = results.compactMap { try? $0.result.get() }
            if apps.isEmpty { model.notice = GuestStore.summary(of: results) }
            apps.forEach(model.openApp)
            if let notice = model.notice { NSLog("[iDesk] %@", notice) }
        }
    }

    private func desktopPoint(_ g: UIGestureRecognizer) -> CGPoint { g.location(in: host.view) }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        model.cursor.position = desktopPoint(g)
        model.click()
    }

    @objc private func held(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        model.cursor.position = desktopPoint(g)
        model.rightClick()
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let p = desktopPoint(g)
        switch g.state {
        case .began:
            let t = g.translation(in: host.view)
            model.cursor.position = CGPoint(x: p.x - t.x, y: p.y - t.y)
            model.mouseDown()
            model.moveCursor(dx: t.x, dy: t.y)
        case .changed:
            model.moveCursor(dx: p.x - lastPan.x, dy: p.y - lastPan.y)
        default:
            model.mouseUp()
        }
        lastPan = p
    }

    @objc private func scrolled(_ g: UIPanGestureRecognizer) {
        let p = desktopPoint(g)
        if g.state == .began { model.cursor.position = p }
        else if g.state == .changed { model.scroll(dx: -(p.x - lastPan.x), dy: -(p.y - lastPan.y)) }
        lastPan = p
    }
}
