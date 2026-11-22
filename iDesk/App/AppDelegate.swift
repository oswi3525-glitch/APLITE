import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        CrashReporter.install()      // guest apps share this process: record it if one takes iDesk down
        _ = OwnSignature.signature   // read APLite's own signature now, before Bundle.main may be swapped
        CookieVault.restore()        // saved login cookies back into WebKit before any page loads
        MouseInput.shared.start()
        ControllerInput.shared.start()
        MediaControl.shared.start()
        UpdateChecker.shared.startChecking()
        LiveUpdate.check()          // data-only refresh; native code still requires a signed IPA
        UIDevice.current.isBatteryMonitoringEnabled = true   // battery level in the taskbar
        ThermalMonitor.shared.start()       // thermal pressure (public API), shown in tray + quick panel
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
