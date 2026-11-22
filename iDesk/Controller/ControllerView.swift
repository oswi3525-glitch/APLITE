import SwiftUI
import AVKit

/// iPhone UI: status, trackpad (with its buttons) and compose field. Everything else is on the desktop:
/// web windows have their own address bar, the taskbar and app menu open apps and windows.
struct ControllerView: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject private var devices = MouseInput.shared
    @State private var compose = ""
    @State private var liveTyping = false
    @State private var showApps = false
    @State private var showSettings = false
    @State private var showMouseCheck = false
    /// The first-run guide, shown once (not in preview mode, which tests the desktop).
    @State private var showWelcome = !UserDefaults.standard.bool(forKey: WelcomeView.seenKey) && !PreviewController.isRequested
    /// Mouse mode: iPhone held in landscape, the whole screen mirrors the desktop for the AssistiveTouch pointer.
    @State private var mouseMode = false
    @State private var assistiveTouch = UIAccessibility.isAssistiveTouchRunning
    @AppStorage(InputSettings.alwaysShowMouseModeKey) private var alwaysShowMouseMode = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ObservedObject private var voice = VoiceTyping.shared
    @FocusState private var field: Field?

    private enum Field { case compose }

    var body: some View {
        ZStack {
            // Keep the key catcher outermost so switching modes does not lose the keyboard.
            KeyCapture(isActive: typingToDesktop, showsKeyboard: liveTyping, model: model)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)
            if model.isLocked {
                LockedRemote(model: model)
            } else if let state = model.presentation {
                PresentationRemote(model: model, state: state)
            } else if landscape {
                trackpadArea          // landscape: the trackpad fills the screen
            } else {
                VStack(spacing: 10) {
                    header
                    UpdateBanner()
                    VoiceTypingBanner()
                    trackpadArea
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    composeBar
                    if model.isExternalConnected && field == nil && liveTyping {
                        Label("Live typing", systemImage: "keyboard.fill")
                            .font(.caption).foregroundStyle(.green.opacity(0.8))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: field) { _, f in
            if f != nil { liveTyping = false }
            updateKeyboardMode()
        }
        .onChange(of: liveTyping) { _, _ in updateKeyboardMode() }
        .onChange(of: model.isExternalConnected) { _, _ in updateKeyboardMode() }
        #if DEBUG
        .onChange(of: model.isExternalConnected) { _, on in
            guard on, ProcessInfo.processInfo.arguments.contains("-iDeskMouseMode"), !mouseMode else { return }
            mouseMode = true
            PhoneHostingController.setLandscape(true)
        }
        .onAppear { DebugScript.runIfRequested(model) }
        #endif
        .onChange(of: showApps) { _, _ in updateKeyboardMode() }
        .onChange(of: showSettings) { _, _ in updateKeyboardMode() }
        // Chosen from the desktop's right-click menu.
        .onReceive(model.$phoneSheet.compactMap { $0 }) { sheet in
            model.phoneSheet = nil
            guard !showApps, !showSettings, !showWelcome else { return }
            switch sheet {
            case .apps: showApps = true
            case .settings: showSettings = true
            case .welcome: showWelcome = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.assistiveTouchStatusDidChangeNotification)) { _ in
            assistiveTouch = UIAccessibility.isAssistiveTouchRunning
        }
        .sheet(isPresented: $showApps) { AppsSheet(model: model) }
        .sheet(isPresented: $showSettings) { SettingsSheet(model: model) }
        .sheet(isPresented: $showMouseCheck) { MouseCheckView() }
        .fullScreenCover(isPresented: $showWelcome) { WelcomeView() }
        .onChange(of: showWelcome) { _, _ in updateKeyboardMode() }
        .alert("iDesk", isPresented: Binding(get: { model.notice != nil && !showApps && !showSettings && !showWelcome },
                                             set: { if !$0 { model.notice = nil } })) {
            let text = model.crashReport ?? model.notice ?? ""
            if let url = model.crashReportURL {
                Button("Send report") { UIApplication.shared.open(url); model.crashReport = nil }
            }
            Button("Copy error") { UIPasteboard.general.string = text }
            Button("OK", role: .cancel) { model.crashReport = nil }
        } message: {
            Text(model.notice ?? "")
        }
    }

    /// Keys go to the desktop: a display is connected and nothing on the iPhone is being typed into.
    private var typingToDesktop: Bool {
        model.isExternalConnected && field == nil && !showApps && !showSettings && !showWelcome
    }

    private var landscape: Bool { mouseMode || verticalSizeClass == .compact }

    /// The trackpad shows a mirror of the desktop (click where you point) in mouse mode or while
    /// AssistiveTouch is running; otherwise it is a regular trackpad.
    private var mirrorOn: Bool { mouseMode || assistiveTouch }

    /// The mouse mode button stays out of the way until there is a mouse to use it with (AssistiveTouch on, or a
    /// mouse iOS reports), unless Settings → Accessibility keeps it shown. While in mouse mode it is always there.
    private var showMouseModeButton: Bool {
        mouseMode || alwaysShowMouseMode || assistiveTouch || devices.mouseConnected
    }

    private var trackpadArea: some View {
        ZStack(alignment: .topTrailing) {
            TrackpadSurface(mirrorMode: mirrorOn)
            if !(mirrorOn && model.isExternalConnected) {
                trackpadHint.allowsHitTesting(false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 0) {
                roundButton(symbol: "shippingbox", label: "Apps from IPA", caption: "Apps", hint: "Add, install and remove apps") {
                    field = nil
                    // With a display, Apps opens as a window on the desktop.
                    if model.isExternalConnected { model.openPage(.apps) } else { showApps = true }
                }
                roundButton(symbol: liveTyping ? "keyboard.fill" : "keyboard",
                            label: liveTyping ? "Stop live typing" : "Live typing", caption: "Typing",
                            hint: "Each key typed on the iPhone keyboard goes straight to the desktop") {
                    field = nil
                    liveTyping.toggle()
                }
                .disabled(!model.isExternalConnected)
                // Where the sound goes: AirPods, the iPhone, or the display over HDMI. iOS's own picker, which only
                // works with a touch on the iPhone.
                VStack(spacing: 2) {
                    AudioRouteButton()
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(landscape ? Color(white: 0.16) : Color.black.opacity(0.5)).padding(4))
                    if !landscape { buttonCaption("Sound") }
                }
                .padding(4)
                .accessibilityLabel("Audio output")
                .accessibilityHint("Choose where the sound plays: AirPods, the iPhone or the display")
                roundButton(symbol: voice.isListening ? "mic.fill" : "mic", label: voice.isListening ? "Stop voice typing" : "Voice typing",
                            caption: "Voice", hint: "Speak, and the words are typed on the desktop") {
                    field = nil
                    voice.toggle()
                }
                .disabled(!model.isExternalConnected)
                if !model.isExternalConnected {
                    roundButton(symbol: "laptopcomputer", label: "Use a laptop as the display", caption: "Laptop",
                                hint: "Shows the desktop in a laptop's browser on the same Wi-Fi") {
                        LaptopModeController.present()
                    }
                }
                roundButton(symbol: "gearshape", label: "Settings", caption: "Settings",
                            hint: "Brightness, wallpaper, pointer speed") {
                    if model.isExternalConnected { model.openPage(.settings) } else { showSettings = true }
                }
                if showMouseModeButton {
                    roundButton(symbol: mouseMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                label: mouseMode ? "Exit mouse mode" : "Mouse mode", caption: "Mouse",
                                hint: "Turns the iPhone landscape and fills the screen with the desktop to point at") {
                        field = nil
                        mouseMode.toggle()
                        PhoneHostingController.setLandscape(mouseMode)
                    }
                }
            }
        }
        // Portrait: a gray pad framed in black. Landscape: the pad is the whole screen, pure black like the rest.
        .background((landscape ? Color.black : Color(white: 0.13)).ignoresSafeArea())
    }

    private func roundButton(symbol: String, label: LocalizedStringKey, caption: LocalizedStringKey, hint: LocalizedStringKey,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(landscape ? Color(white: 0.16) : Color.black.opacity(0.5)).padding(4))
                // In portrait each button says what it is; in landscape (mouse mode) the desktop needs the room.
                if !landscape { buttonCaption(caption) }
            }
        }
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .padding(4)
    }

    private func buttonCaption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .lineLimit(1)
            .frame(width: 56)
    }

    /// Tell PhoneWindow where hardware key presses should go.
    private func updateKeyboardMode() {
        // A sheet with text fields (e.g. a password) is open: let keys go there.
        PhoneWindow.mode = typingToDesktop ? .special : .off
        PhoneWindow.current?.claimKeyboard()
    }

    private var header: some View {
        VStack(spacing: 4) {
        HStack {
            Image(systemName: model.isExternalConnected ? "display" : "display.trianglebadge.exclamationmark")
                .foregroundStyle(model.isExternalConnected ? .green : .orange)
            Text(model.isExternalConnected ? "External display connected" : "No external display")
                .font(.subheadline.weight(.medium))
            Spacer()
            Text("\(model.windows.count) windows").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        deviceStatus
        }
    }

    /// Shows whether a real mouse / keyboard is being received.
    private var deviceStatus: some View {
        HStack(spacing: 14) {
            // Tap: the Mouse check screen (what iOS delivers from the mouse, through each path).
            Button { showMouseCheck = true } label: {
                Label(mouseText, systemImage: "computermouse")
                    .foregroundStyle(devices.mouseActive ? .green : devices.mouseConnected ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows what the mouse sends to iDesk")
            Label(devices.keyboardConnected ? "Keyboard: connected" : "Keyboard: none",
                  systemImage: "keyboard")
                .foregroundStyle(devices.keyboardConnected ? .green : .secondary)
            Spacer()
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }

    private var mouseText: String {
        switch devices.source {
        case .gameController: return String(localized: "Mouse: working (GameController)")
        case .assistiveTouch: return String(localized: "Mouse: working (AssistiveTouch)")
        case .none:
            return devices.mouseConnected ? String(localized: "Mouse: detected, try moving it") : String(localized: "Mouse: not detected, see the guide")
        }
    }

    private var trackpadHint: some View {
        Group {
            if model.isExternalConnected {
                // The gestures, one icon and a word each.
                LazyVGrid(columns: [GridItem(.fixed(130)), GridItem(.fixed(130))], spacing: 22) {
                    gesture("cursorarrow.motionlines", "1 finger", "Move")
                    gesture("hand.tap", "Tap", "Click")
                    gesture("arrow.up.and.down", "2 fingers", "Scroll")
                    gesture("square.stack.3d.up", "3 fingers", "Switch apps")
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "display").font(.system(size: 34, weight: .light))
                    Text("Connect a display").font(.subheadline)
                }
            }
        }
        .foregroundStyle(.white.opacity(0.3))
        .padding()
    }

    private func gesture(_ symbol: String, _ title: LocalizedStringKey, _ action: LocalizedStringKey) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light))
                .frame(width: 52, height: 52)
                .background(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
            Text(title).font(.caption.weight(.semibold))
            Text(action).font(.caption2).foregroundStyle(.white.opacity(0.22))
        }
    }

    /// Compose field: full IME support (e.g. Vietnamese Telex/VNI); Send types the text into the page.
    private var composeBar: some View {
        HStack(spacing: 8) {
            TextField("Type text to send to the page", text: $compose)
                .focused($field, equals: .compose)
                .submitLabel(.send)
                .onSubmit { sendCompose(withEnter: true) }
            if compose.isEmpty {
                // iOS's own paste button: no "Allow paste?" question, and a password copied from the Passwords app
                // or a password manager goes straight into the page's field.
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first, !text.isEmpty else { return }
                    DispatchQueue.main.async { model.typeText(text) }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
                .tint(Color(white: 0.3))
                .accessibilityHint("Types what you copied on the iPhone into the page")
            } else {
                Button { sendCompose(withEnter: false) } label: {
                    Image(systemName: "paperplane.fill").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Send text")
            }
        }
        .padding(.leading, 12)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.16)))
        .disabled(!model.isExternalConnected)
        .opacity(model.isExternalConnected ? 1 : 0.4)
    }

    private func sendCompose(withEnter: Bool) {
        if !compose.isEmpty { model.typeText(compose) }
        if withEnter { model.pressEnter() }
        compose = ""
    }
}

/// iOS's audio output picker (AirPods and other Bluetooth headphones, AirPlay, the iPhone speaker, the display).
private struct AudioRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = UIColor.white.withAlphaComponent(0.75)
        picker.activeTintColor = .systemBlue
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

