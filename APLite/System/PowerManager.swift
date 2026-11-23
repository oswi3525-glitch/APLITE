import Foundation
import UIKit

/// APLite's software power states. This is **not** hardware power control: iOS never lets an app
/// switch the iPhone or iPad off, and code loaded into a process cannot be unloaded. "Shutdown"
/// closes APLite's desktop, suspends every guest app and releases what can be released; "Sleep"
/// pauses work and locks; "Wake" resumes and asks for authentication when configured.
enum PowerState: String {
    case running, sleeping, shuttingDown, shutDown

    var label: String {
        switch self {
        case .running: return String(localized: "Running")
        case .sleeping: return String(localized: "Asleep")
        case .shuttingDown: return String(localized: "Shutting down…")
        case .shutDown: return String(localized: "Shut down")
        }
    }
}

final class PowerManager: ObservableObject {
    static let shared = PowerManager()

    @Published private(set) var state: PowerState = .running
    @Published private(set) var lastChange = Date()

    private init() {}

    // MARK: Transitions

    func sleep() {
        guard state == .running else { return }
        set(.sleeping)
        let model = DesktopModel.shared
        if APLiteSettings.Power.suspendWorkOnSleep {
            for window in model.windows {
                if let guest = window.guestWindow { GuestRuntime.suspendApp(with: guest) }
            }
            QuickLook.stop()
        }
        if APLiteSettings.Security.lockWhenSleeping { model.lockDesktop(force: true) }
        // Keep the session: sleep must not lose the desktop the user left behind.
        APLiteSettings.System.cleanShutdown = true
    }

    func wake() {
        guard state == .sleeping else { return }
        set(.running)
        let model = DesktopModel.shared
        for window in model.windows {
            if let guest = window.guestWindow { GuestRuntime.resumeApp(with: guest) }
        }
        AudioSessionManager.shared.activatePlayback(reason: "wake")
        if APLiteSettings.Security.authenticateOnWake { model.lockDesktop(force: true) }
    }

    func shutdown() {
        guard state != .shutDown else { return }
        set(.shuttingDown)
        let model = DesktopModel.shared
        APLiteSettings.System.savedSession = model.windows.compactMap { $0.currentURL.absoluteString }
        APLiteSettings.System.lastShutdown = Date()
        APLiteSettings.System.cleanShutdown = true
        // Existing close() already suspends the guest and schedules a state save.
        for window in Array(model.windows) { model.close(window) }
        model.closePanels()
        QuickLook.stop()
        AccountCookies.shared.flush()   // keep accounts signed in after a shut down / restart
        MemoryManager.shared.releaseCaches(reason: "shutdown")
        set(.shutDown)
    }

    /// Starting (or restarting) the APLite environment after a shutdown.
    func boot() {
        guard state == .shutDown else { return }
        set(.running)
        restoreSessionIfNeeded()
    }

    private var pendingRestore: [String] = []

    /// Called once from AppDelegate. Restores the session only for a clean previous shutdown.
    func restoreSessionIfNeeded() {
        guard APLiteSettings.Power.restoreSessionOnLaunch, APLiteSettings.System.cleanShutdown else { return }
        let saved = APLiteSettings.System.savedSession
        guard !saved.isEmpty else { return }
        let model = DesktopModel.shared
        // At launch the external display is not connected yet and openWindow() intentionally
        // refuses to create invisible windows. Keep the session and retry when the display arrives.
        guard model.isExternalConnected else { pendingRestore = saved; return }
        apply(saved)
    }

    /// Called when the external display connects, to finish a restore deferred at launch.
    func restorePendingSessionIfNeeded() {
        guard !pendingRestore.isEmpty, DesktopModel.shared.isExternalConnected else { return }
        let saved = pendingRestore
        pendingRestore = []
        apply(saved)
    }

    private func apply(_ saved: [String]) {
        let model = DesktopModel.shared
        if model.windows.isEmpty {
            for value in saved {
                guard let url = URL(string: value) else { continue }
                model.openWindow(url.absoluteString)
            }
        }
        APLiteSettings.System.savedSession = []
    }

    /// If the app was killed uncleanly, remember it so the next launch can offer a safe state.
    func noteAbnormalTermination() { APLiteSettings.System.cleanShutdown = false }

    private func set(_ new: PowerState) {
        state = new
        lastChange = Date()
    }
}
