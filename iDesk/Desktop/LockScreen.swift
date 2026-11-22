import SwiftUI
import LocalAuthentication

/// Settings → Security: the desktop can lock (⌃⌘Q, when iDesk comes back after the iPhone was locked or another app
/// was used, and after the screen saver) and opens again with Face ID, Touch ID or the passcode on the iPhone. The
/// screen saver (a big clock) starts after some minutes without input.
enum LockSettings {
    private static let lockKey = "iDesk.lockWithFaceID", saverKey = "iDesk.screenSaverMinutes"
    static var lockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: lockKey) }
        set { UserDefaults.standard.set(newValue, forKey: lockKey) }
    }
    /// 0 = never.
    static var saverMinutes: Int {
        get { UserDefaults.standard.object(forKey: saverKey) as? Int ?? 10 }
        set { UserDefaults.standard.set(newValue, forKey: saverKey) }
    }
    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return String(localized: "the passcode")
        }
    }
}

extension DesktopModel {
    /// Locks the desktop (when locking is turned on, or asked for by ⌃⌘Q).
    func lockDesktop(force: Bool = false) {
        guard force || LockSettings.lockEnabled, isExternalConnected, !isLocked else { return }
        closePanels()
        isLocked = true
    }

    /// Asks for Face ID / Touch ID / the passcode on the iPhone and unlocks.
    func unlockDesktop() {
        let ctx = LAContext()
        ctx.localizedCancelTitle = String(localized: "Cancel")
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Unlock the desktop")) { ok, _ in
            DispatchQueue.main.async { if ok { self.isLocked = false; self.lastInput = Date() } }
        }
    }

    /// Any input: the screen saver ends (and the clock for the next one restarts).
    func noteInput() {
        lastInput = Date()
        if showScreenSaver {
            withAnimation(.easeOut(duration: 0.3)) { showScreenSaver = false }
            lockDesktop()
        }
    }

    /// Every few seconds: starts the screen saver after the chosen idle time (not while a video plays fullscreen).
    func checkIdle() {
        let minutes = LockSettings.saverMinutes
        guard minutes > 0, isExternalConnected, !showScreenSaver, !hasFullscreen, presentation == nil,
              !ScreenRecorder.shared.isRecording,
              Date().timeIntervalSince(lastInput) > Double(minutes * 60) else { return }
        closePanels()
        withAnimation(.easeIn(duration: 0.8)) { showScreenSaver = true }
    }
}

/// The big clock of the screen saver, drifting slowly so nothing burns into the display.
struct ScreenSaverView: View {
    let size: CGSize
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            // Within the screen: the clock is about 600 × 220 points.
            let dx = CGFloat(sin(t / 37)) * max(0, size.width / 2 - 340), dy = CGFloat(cos(t / 53)) * max(0, size.height / 2 - 160)
            ZStack {
                Color.black
                VStack(spacing: 8) {
                    Text(ctx.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 150, weight: .thin, design: .rounded).monospacedDigit())
                    Text(ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .foregroundStyle(.white.opacity(0.85))
                .offset(x: dx, y: dy)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }
}

/// The locked desktop: the wallpaper blurred, the time, and how to open it.
struct LockScreenView: View {
    @ObservedObject var model: DesktopModel
    let size: CGSize
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            ZStack {
                Color.black          // nothing of the desktop shows through the blur's edges
                WallpaperView(index: model.wallpaper, image: model.customWallpaper,
                              blur: CGFloat(model.wallpaperBlur) + 18, watermark: false)
                    .blur(radius: 40, opaque: true)
                    .overlay(Color.black.opacity(0.35))
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill").font(.system(size: 34))
                    Text(ctx.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 110, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 24, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                    Text(verbatim: Device.words(String(localized: "Unlock on the iPhone with \(LockSettings.biometryName)")))
                        .font(.system(size: 18, weight: .medium))
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 30)
                }
                .foregroundStyle(.white)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }
}

/// On the iPhone while the desktop is locked.
struct LockedRemote: View {
    @ObservedObject var model: DesktopModel
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "lock.display").font(.system(size: 64)).foregroundStyle(.tint)
            Text("The desktop is locked").font(.title2.bold())
            Button { model.unlockDesktop() } label: {
                Label(String(localized: "Unlock with \(LockSettings.biometryName)"), systemImage: "faceid")
                    .font(.headline).frame(maxWidth: 360, minHeight: 54)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(24)
        .onAppear { model.unlockDesktop() }
    }
}

