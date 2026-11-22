import UIKit
import SwiftUI

/// iPhone screen: trackpad + address bar + keyboard.
final class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = PhoneWindow(windowScene: windowScene)
        window.rootViewController = PreviewController.isRequested
            ? PreviewController()
            : PhoneHostingController(rootView: ControllerView(model: .shared))
        window.makeKeyAndVisible()
        PhoneWindow.current = window
        window.claimKeyboard()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        PhoneWindow.current?.claimKeyboard()
        GuestRuntime.forwardSceneEvent(#selector(UISceneDelegate.sceneDidBecomeActive(_:)), scene: scene)
    }

    // The guest app has no scene of its own: forward the iPhone scene's lifecycle events to it.
    func sceneWillResignActive(_ scene: UIScene) {
        GuestRuntime.forwardSceneEvent(#selector(UISceneDelegate.sceneWillResignActive(_:)), scene: scene)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        GuestRuntime.forwardSceneEvent(#selector(UISceneDelegate.sceneDidEnterBackground(_:)), scene: scene)
        MemoryManager.shared.releaseCaches(reason: "background")
        GoogleSession.save()   // keep the signed-in Google account in APLite's cookie vault
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        GuestRuntime.forwardSceneEvent(#selector(UISceneDelegate.sceneWillEnterForeground(_:)), scene: scene)
        MemoryManager.shared.sample()
    }

    /// "Open in APLite" from Files / a signing app: install the shared IPAs.
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        let ipas = URLContexts.map(\.url).filter { $0.pathExtension.lowercased() == "ipa" }
        GuestStore.shared.install(ipas: ipas) { results in
            var next: String?
            #if !targetEnvironment(simulator)
            if !GuestStore.canLoadOutsideBundle { next = LaunchDiagnostics.installTip }
            #endif
            DesktopModel.shared.notice = GuestStore.summary(of: results, next: next)
        }
    }
}

/// Controller screen on the iPhone: follows device rotation; mouse mode is always landscape.
final class PhoneHostingController: UIHostingController<ControllerView> {
    private static var landscapeOnly = false

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        Self.landscapeOnly ? .landscape : UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    /// Three-finger swipes are trackpad gestures here, not iOS's undo / redo / copy gestures.
    override var editingInteractionConfiguration: UIEditingInteractionConfiguration { .none }

    static func setLandscape(_ on: Bool) {
        landscapeOnly = on
        guard let window = PhoneWindow.current, let scene = window.windowScene else { return }
        window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        // Entering mouse mode: rotate to landscape now. Leaving: back to portrait, unless the iPhone is held sideways.
        // (Only allowing portrait again is not enough: with rotation lock on, iOS would keep the screen landscape.)
        if on, !scene.interfaceOrientation.isLandscape {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
        } else if !on, scene.interfaceOrientation.isLandscape, !UIDevice.current.orientation.isLandscape {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
        }
    }
}

/// External display (HDMI/USB-C): shows the desktop. This scene receives no touches,
/// so all input goes through DesktopModel (self-drawn pointer + own hit testing).
final class ExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    /// The desktop view on the external display, mirrored on the iPhone in mouse mode.
    static weak var desktopView: UIView?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        ExternalDisplay.connected(windowScene.screen)
        let model = DesktopModel.shared
        model.screenSize = windowScene.coordinateSpace.bounds.size

        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = .dark          // menus and panels match iDesk's dark windows
        let host = UIHostingController(rootView: DesktopView(model: model))
        host.view.backgroundColor = .black
        window.rootViewController = host
        window.isHidden = false
        Self.desktopView = host.view
        self.window = window
        // A new resolution (automatic at connection, or from Settings): the desktop takes the screen's new size.
        // The scene does not resize its window by itself when the mode changes after the window exists.
        modeObserver = NotificationCenter.default.addObserver(forName: UIScreen.modeDidChangeNotification,
                                                              object: windowScene.screen, queue: .main) { [weak self] _ in
            self?.fitToScreen()
        }
        DispatchQueue.main.async { [weak self] in self?.fitToScreen() }

        model.externalConnected()
    }

    private var modeObserver: NSObjectProtocol?

    private func fitToScreen() {
        guard let window, let screen = window.windowScene?.screen else { return }
        let size = screen.bounds.size
        guard size.width > 0, window.frame.size != size else { return }
        window.frame = CGRect(origin: .zero, size: size)
        DesktopModel.shared.screenSize = size
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        if let modeObserver { NotificationCenter.default.removeObserver(modeObserver) }
        modeObserver = nil
        DesktopModel.shared.externalDisconnected()
        ExternalDisplay.disconnected()
        window = nil
    }
}
