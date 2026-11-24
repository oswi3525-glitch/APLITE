import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        BootCoordinator.shared.start(steps: [
            .init(phase: .initializing) {
                CrashReporter.install()      // guest apps share this process: record it if one takes APLite down
                _ = OwnSignature.signature   // read APLite's own signature now, before Bundle.main may be swapped
                CookieVault.restore()        // saved login cookies back into WebKit before any page loads
            },
            .init(phase: .loadingResources) {
                AccountCookies.shared.start() // then watch the store: logins on the external display are saved too
                MouseInput.shared.start()
                ControllerInput.shared.start()
                // One owner for the process-wide audio session. Guest apps, WebKit, Quick Look and speech all
                // share it; starting it before MediaControl also fixes the silent-switch-sensitive default
                // category that made the desktop silent over HDMI / AirPlay.
                // Audio activates during boot step 2 and calls these closures immediately. DesktopModel.shared
                // owns the guest-app scan, keychain reads and cache checks; forcing it here put that heavy
                // singleton init on the boot main thread. Before services are ready there are no windows or
                // tabs to inspect anyway, so report the safe answer and let the real state take over later.
                AudioSessionManager.shared.guestAppsActive = {
                    guard BootCoordinator.shared.servicesReady else { return false }
                    // A minimised or off-desk guest can still be playing audio. "Shown" is not a proxy for
                    // "silent": keeping the session for any live guest window avoids cutting its sound.
                    return DesktopModel.shared.windows.contains { $0.guestWindow != nil }
                }
                AudioSessionManager.shared.audioInUse = {
                    let basic = QuickLook.isActive || ReadAloud.shared.isSpeaking || WebAudioActivity.shared.isPlaying
                    guard BootCoordinator.shared.servicesReady else { return basic }
                    return basic || DesktopModel.shared.windows.contains { $0.guestWindow != nil && $0.isShown }
                }
                // Web Audio contexts can stay suspended after an interruption; nudge every open tab.
                AudioSessionManager.shared.resumeWebAudio = {
                    guard BootCoordinator.shared.servicesReady else { return }
                    for window in DesktopModel.shared.windows {
                        for tab in window.tabs {
                            tab.evaluateJavaScript("window.__ideskVolumeResume && window.__ideskVolumeResume()")
                        }
                    }
                }
                AudioSessionManager.shared.start()
                MediaControl.shared.start()
            },
            .init(phase: .startingServices) {
                MemoryManager.shared.start()        // 1 GB target, peak, warnings and leak hints
                CacheManager.shared.start()         // bound WebKit / URL caches on long sessions
                PowerManager.shared.restoreSessionIfNeeded()
                UpdateChecker.shared.startChecking()
                LiveUpdate.check()          // data-only refresh; native code still requires a signed IPA
                BuiltInWebApps.installOnFirstLaunchIfNeeded()   // Zalo, Facebook, Telegram, … on the desktop
                UIDevice.current.isBatteryMonitoringEnabled = true   // battery level in the taskbar
                ThermalMonitor.shared.start()       // thermal pressure (public API), shown in tray + quick panel
            },
        ])
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
