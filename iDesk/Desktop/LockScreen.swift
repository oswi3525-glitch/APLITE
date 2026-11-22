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
    /// 0 = never. The Settings page offers 1, 2, 5, 10, 15, 30 and 60 minutes.
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

/// APLite's configurable screen saver. Everything is local (UserDefaults) and read when the saver
/// starts, so changing a setting does not require an app restart.
enum ScreenSaverStyle: Int, CaseIterable {
    case clock = 0
    case gradient = 1
    case wallpaper = 2
}

enum ScreenSaverSettings {
    static let styleKey = "APLite.saverStyle"
    static let motionKey = "APLite.saverMotion"
    static let fadeKey = "APLite.saverFade"

    static var style: ScreenSaverStyle {
        get { ScreenSaverStyle(rawValue: UserDefaults.standard.integer(forKey: styleKey)) ?? .clock }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: styleKey) }
    }
    /// The slow drift protects OLED screens from burn-in; turn it off for a still image.
    static var motion: Bool {
        get { UserDefaults.standard.object(forKey: motionKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: motionKey) }
    }
    /// Seconds for the fade in/out of the saver.
    static var fade: Double {
        get {
            let value = UserDefaults.standard.object(forKey: fadeKey) as? Double ?? 0.8
            return min(2, max(0.2, value))
        }
        set { UserDefaults.standard.set(min(2, max(0.2, newValue)), forKey: fadeKey) }
    }
    static let minuteOptions = [1, 2, 5, 10, 15, 30, 60]
}

extension DesktopModel {
    /// Locks the desktop (when locking is turned on, or asked for by ⌃⌘Q).
    func lockDesktop(force: Bool = false) {
        guard force || LockSettings.lockEnabled, isExternalConnected, !isLocked else { return }
        closePanels()
        isLocked = true
        SecurityManager.shared.lock()   // keep APLite's security state in sync with the view
    }

    /// Asks for Face ID / Touch ID / the passcode on the iPhone and unlocks.
    func unlockDesktop() {
        let ctx = LAContext()
        ctx.localizedCancelTitle = String(localized: "Cancel")
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Unlock the desktop")) { ok, _ in
            DispatchQueue.main.async {
                guard ok else { return }
                self.isLocked = false
                SecurityManager.shared.unlock()
                self.lastInput = Date()
            }
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
        withAnimation(.easeIn(duration: ScreenSaverSettings.fade)) { showScreenSaver = true }
    }
}

/// The screen saver: a drifting clock by default, an APLite gradient, or the blurred wallpaper.
/// `size` is the external display's size; the clock stays readable on a TV across the room.
struct ScreenSaverView: View {
    let size: CGSize
    var wallpaperIndex: Int = 0
    var wallpaper: UIImage?
    var wallpaperBlur: Double = 0
    var performance = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let drift = ScreenSaverSettings.motion
            let dx = drift ? CGFloat(sin(t / 37)) * max(0, size.width / 2 - 340) : 0
            let dy = drift ? CGFloat(cos(t / 53)) * max(0, size.height / 2 - 160) : 0
            ZStack {
                switch ScreenSaverSettings.style {
                case .gradient:
                    LinearGradient(colors: Wallpapers.all[0], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(alignment: .center) {
                            Text(verbatim: APLite.name)
                                .font(.system(size: min(size.width, size.height) * 0.18, weight: .black, design: .rounded))
                                .foregroundStyle(.white.opacity(0.22))
                        }
                        .animation(.easeInOut(duration: 4), value: ctx.date)
                case .wallpaper:
                    WallpaperView(index: wallpaperIndex, image: wallpaper,
                                  blur: CGFloat(wallpaperBlur) + 14, watermark: false)
                    Color.black.opacity(0.32)
                    clock(ctx.date, dx: dx, dy: dy, compact: true)
                case .clock:
                    Color.black
                    clock(ctx.date, dx: dx, dy: dy, compact: false)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func clock(_ date: Date, dx: CGFloat, dy: CGFloat, compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 8) {
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: compact ? 84 : 150, weight: .thin, design: .rounded).monospacedDigit())
            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(size: compact ? 20 : 30, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(.white.opacity(0.85))
        .offset(x: dx, y: dy)
    }
}

/// The locked desktop: the wallpaper blurred, the time, and how to open it.
struct LockScreenView: View {
    @ObservedObject var model: DesktopModel
    let size: CGSize
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            ZStack {
                Color.black
                // One blur, applied by WallpaperView with an over-scale so no transparent edges
                // appear on a photo. The old extra .blur(40) cost a second full-screen pass.
                WallpaperView(index: model.wallpaper, image: model.customWallpaper,
                              blur: CGFloat(model.wallpaperBlur) + 30,
                              performance: model.performanceMode, watermark: false)
                LinearGradient(colors: [Color.black.opacity(0.18), Color.black.opacity(0.58)],
                               startPoint: .top, endPoint: .bottom)
                VStack(spacing: 10) {
                    Group {
                        if let mark = UIImage(named: "LockMark") {
                            Image(uiImage: mark).resizable().frame(width: 44, height: 44)
                        } else {
                            Image(systemName: "lock.fill").font(.system(size: 34))
                        }
                    }
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
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

/// APLite's own passcode entry. The passcode never leaves this view: it is compared against a
/// salted hash in the Keychain by SecurityManager, which also enforces the lockout.
private struct PasscodeUnlockView: View {
    @ObservedObject private var security = SecurityManager.shared
    @State private var code = ""
    @State private var message: String?
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            SecureField(String(localized: "APLite passcode"), text: $code)
                .textContentType(.password)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
                .onSubmit(verify)
            if let message {
                Text(message).font(.footnote).foregroundStyle(.red)
                    .multilineTextAlignment(.center).frame(maxWidth: 300)
            }
            if let deadline = security.lockoutUntil, deadline > Date() {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(String(format: String(localized: "Try again in %d s"),
                                max(0, Int(deadline.timeIntervalSince(ctx.date)))))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Button(action: verify) {
                Label(String(localized: "Unlock"), systemImage: "lock.open")
                    .frame(maxWidth: 260, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(code.isEmpty)
        }
    }

    private func verify() {
        do {
            try security.verifyPasscode(code)
            code = ""
            message = nil
            security.unlock()
            onUnlock()
        } catch {
            code = ""
            message = error.localizedDescription
        }
    }
}

/// On the iPhone while the desktop is locked.
struct LockedRemote: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject private var security = SecurityManager.shared

    private func opened() {
        model.isLocked = false
        model.lastInput = Date()
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "lock.display").font(.system(size: 64)).foregroundStyle(.tint)
            Text("The desktop is locked").font(.title2.bold())
            if security.isConfigured {
                PasscodeUnlockView(onUnlock: opened)
                Button { model.unlockDesktop() } label: {
                    Label(String(localized: "Use \(LockSettings.biometryName) instead"), systemImage: "faceid")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            } else {
                Button { model.unlockDesktop() } label: {
                    Label(String(localized: "Unlock with \(LockSettings.biometryName)"), systemImage: "faceid")
                        .font(.headline).frame(maxWidth: 360, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding(24)
        .onAppear {
            // Never auto-prompt when APLite's own passcode is required — that would bypass it.
            if !security.isConfigured { model.unlockDesktop() }
        }
    }
}

