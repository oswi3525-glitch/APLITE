import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        CrashReporter.install()      // guest apps share this process: record it if one takes iDesk down
        _ = OwnSignature.signature   // read iDesk's own signature now, before Bundle.main may be swapped
        MouseInput.shared.start()
        ControllerInput.shared.start()
        MediaControl.shared.start()
        UpdateChecker.shared.startChecking()
        UIDevice.current.isBatteryMonitoringEnabled = true   // battery level in the taskbar
        return true
    }

    // Pick the scene delegate by role: the iPhone screen (controller) or the external display (desktop).
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if session.role == .windowExternalDisplayNonInteractive {
            let config = UISceneConfiguration(name: "External", sessionRole: session.role)
            config.delegateClass = ExternalSceneDelegate.self
            return config
        }
        let config = UISceneConfiguration(name: "Phone", sessionRole: session.role)
        config.delegateClass = PhoneSceneDelegate.self
        return config
    }
}
