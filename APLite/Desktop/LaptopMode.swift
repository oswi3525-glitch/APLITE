import UIKit
import SwiftUI
import Combine

/// "Use a laptop as the display": the desktop runs on the iPhone (shown small, and touchable, like preview mode) and
/// RemoteDisplay sends it to a browser on the laptop, which also sends back its mouse and keyboard.
final class LaptopModeController: UIViewController {
    private let model = DesktopModel.shared
    private var desktopSize = RemoteDisplay.shared.desktopSize
    private var sizeWatch: AnyCancellable?
    private lazy var host = UIHostingController(rootView: DesktopView(model: model))
    private lazy var header = UIHostingController(rootView: LaptopHeader())
    private lazy var footer = UIHostingController(rootView: LaptopFooter { [weak self] in self?.stop() })
    /// The rounded, lit frame the small desktop sits in.
    private let card = UIView()
    private var lastPan: CGPoint = .zero

    /// Starts laptop mode on the iPhone (only without a real display: a cable or AirPlay is better).
    static func present() {
        guard !DesktopModel.shared.isExternalConnected, var top = PhoneWindow.current?.rootViewController else { return }
        while let p = top.presentedViewController, !p.isBeingDismissed { top = p }
        let vc = LaptopModeController()
        vc.modalPresentationStyle = .fullScreen
        top.present(vc, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark
        model.screenSize = desktopSize

        for hc in [header, footer] as [UIViewController] {
            addChild(hc)
            hc.view.backgroundColor = .clear
            view.addSubview(hc.view)
            hc.didMove(toParent: self)
        }
        card.backgroundColor = UIColor(white: 0.08, alpha: 1)
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        card.layer.shadowColor = UIColor.systemBlue.cgColor
        card.layer.shadowOpacity = 0.25
        card.layer.shadowRadius = 24
        view.addSubview(card)

        host.overrideUserInterfaceStyle = .dark
        addChild(host)
        host.view.layer.anchorPoint = .zero
        host.view.bounds = CGRect(origin: .zero, size: desktopSize)
        host.view.backgroundColor = .black
        host.view.layer.masksToBounds = true
        view.addSubview(host.view)
        host.didMove(toParent: self)
        ExternalSceneDelegate.desktopView = host.view

        // Touching the small desktop works too (see PreviewController): taps click, drags drag, hold = right click.
        let shield = UIView()
        shield.tag = 7
        view.addSubview(shield)
        shield.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
        pan.maximumNumberOfTouches = 1
        shield.addGestureRecognizer(pan)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held))
        hold.minimumPressDuration = 0.6
        pan.require(toFail: hold)
        shield.addGestureRecognizer(hold)

        model.externalConnected()
        RemoteDisplay.shared.start()
        // The laptop's window has another shape: the desktop takes it (windows are fitted to the new size).
        sizeWatch = RemoteDisplay.shared.$desktopSize.dropFirst().removeDuplicates().sink { [weak self] size in
            guard let self else { return }
            desktopSize = size
            host.view.bounds = CGRect(origin: .zero, size: size)
            model.screenSize = size
            view.setNeedsLayout()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaLayoutGuide.layoutFrame
        let headerHeight: CGFloat = 250, footerHeight: CGFloat = 96
        header.view.frame = CGRect(x: safe.minX, y: safe.minY, width: safe.width, height: headerHeight)
        footer.view.frame = CGRect(x: safe.minX, y: safe.maxY - footerHeight, width: safe.width, height: footerHeight)
        // The desktop, as large as fits between them, in the middle.
        let area = CGRect(x: safe.minX + 20, y: safe.minY + headerHeight, width: safe.width - 40,
                          height: safe.height - headerHeight - footerHeight).insetBy(dx: 0, dy: 10)
        let s = min(area.width / desktopSize.width, area.height / desktopSize.height)
        let w = desktopSize.width * s, h = desktopSize.height * s
        let frame = CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
        host.view.transform = CGAffineTransform(scaleX: s, y: s)
        host.view.layer.position = frame.origin
        host.view.layer.cornerRadius = 14 / s
        card.frame = frame.insetBy(dx: -1, dy: -1)
        view.viewWithTag(7)?.frame = frame
    }

    private func stop() {
        sizeWatch = nil
        RemoteDisplay.shared.stop()
        model.externalDisconnected()
        if ExternalSceneDelegate.desktopView === host.view { ExternalSceneDelegate.desktopView = nil }
        dismiss(animated: true)
    }

    private func point(_ g: UIGestureRecognizer) -> CGPoint { g.location(in: host.view) }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        model.cursor.position = point(g)
        model.click()
    }

    @objc private func held(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        model.cursor.position = point(g)
        model.rightClick()
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let p = point(g)
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
}

/// The top of the iPhone in laptop mode: what to open on the laptop, and whether it is connected.
private struct LaptopHeader: View {
    @ObservedObject var remote = RemoteDisplay.shared
    @State private var copied = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tint)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text("Laptop as the display").font(.title3.weight(.semibold))
            if let failure = remote.failure {
                Text(verbatim: failure).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
            } else if let address = remote.address {
                Button {
                    UIPasteboard.general.string = address
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    HStack(spacing: 10) {
                        Text(verbatim: address.replacingOccurrences(of: "http://", with: ""))
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.subheadline)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                HStack(spacing: 7) {
                    Circle().fill(remote.viewers > 0 ? Color.green : Color.orange).frame(width: 8, height: 8)
                    Text(remote.viewers > 0 ? "Connected" : "Open it in the laptop's browser")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Text("Join the same Wi-Fi as the laptop.").font(.footnote).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LaptopFooter: View {
    let stop: () -> Void
    var body: some View {
        Button(action: stop) {
            Text("Stop").font(.headline).foregroundStyle(.red)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Capsule().fill(Color.red.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
