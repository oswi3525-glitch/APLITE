import SwiftUI
import UIKit

/// A transparent window above the scene's own window. It never participates in desktop layout, so the pill can
/// animate without redrawing the desktop. Touches outside the pill fall through to the app beneath it.
final class DynamicIslandWindow: UIWindow {
    weak var hostView: UIView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        // SwiftUI may return the hosting view itself for empty areas. Let those touches fall through to the
        // desktop; only real pill controls (deeper descendants) may consume them.
        if hit === self || hit === hostView { return nil }
        return hit
    }
}

final class DynamicIslandOverlay {
    static let shared = DynamicIslandOverlay()

    private var phoneWindow: DynamicIslandWindow?
    private var externalWindow: DynamicIslandWindow?

    private init() {}

    func install(in scene: UIWindowScene, role: IslandDisplayRole) {
        let window = DynamicIslandWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .statusBar + 1
        let host = UIHostingController(rootView: DynamicIslandView(role: role))
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        window.rootViewController = host
        window.hostView = host.view
        window.isHidden = false
        switch role {
        case .phone: phoneWindow = window
        case .external: externalWindow = window
        }
    }

    func remove(role: IslandDisplayRole) {
        switch role {
        case .phone: phoneWindow?.isHidden = true; phoneWindow = nil
        case .external: externalWindow?.isHidden = true; externalWindow = nil
        }
    }

    private var activeWindow: DynamicIslandWindow? {
        DesktopModel.shared.isExternalConnected ? externalWindow : phoneWindow
    }

    /// Converts a cursor position in the desktop's logical coordinate space into overlay-window coordinates.
    private func convert(_ point: CGPoint) -> CGPoint? {
        guard activeWindow != nil else { return nil }
        if DesktopModel.shared.isExternalConnected { return point }
        guard let frame = DesktopModel.shared.desktopDisplayFrame,
              frame.width > 0, frame.height > 0 else { return nil }
        let screen = DesktopModel.shared.screenSize
        guard screen.width > 0, screen.height > 0 else { return nil }
        return CGPoint(x: frame.minX + point.x / screen.width * frame.width,
                       y: frame.minY + point.y / screen.height * frame.height)
    }

    func pointerDown(at desktopPoint: CGPoint) -> Bool {
        guard let point = convert(desktopPoint) else { return false }
        return NowPlayingService.shared.pointerDown(at: point)
    }

    @discardableResult
    func pointerUp(at desktopPoint: CGPoint) -> Bool {
        guard let point = convert(desktopPoint) else { return false }
        return NowPlayingService.shared.pointerUp(at: point)
    }

    func secondaryClick(at desktopPoint: CGPoint) -> Bool {
        guard let point = convert(desktopPoint) else { return false }
        return NowPlayingService.shared.secondaryClick(at: point)
    }
}
