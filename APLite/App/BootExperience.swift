import SwiftUI
import Combine

@MainActor
final class BootCoordinator: ObservableObject {
    enum Phase: Equatable {
        case initializing
        case loadingResources
        case startingServices
        case preparingDesktop
        case ready
        case failed

        var title: String {
            switch self {
            case .initializing: return String(localized: "Initializing system")
            case .loadingResources: return String(localized: "Loading resources")
            case .startingServices: return String(localized: "Starting services")
            case .preparingDesktop: return String(localized: "Preparing desktop")
            case .ready: return String(localized: "Ready")
            case .failed: return String(localized: "Startup needs attention")
            }
        }

        var progress: Double {
            switch self {
            case .initializing: return 0.15
            case .loadingResources: return 0.4
            case .startingServices: return 0.68
            case .preparingDesktop: return 0.9
            case .ready: return 1
            case .failed: return 0
            }
        }
    }

    struct StartupStep {
        let phase: Phase
        let operation: () throws -> Void
    }

    static let shared = BootCoordinator()

    @Published private(set) var phase: Phase = .initializing
    @Published private(set) var servicesReady = false
    @Published private(set) var desktopReady = false
    @Published private(set) var errorMessage: String?

    /// Safety net only: a service that never returns must not strand the user on the boot
    /// screen forever. Progress is still event-driven — this is not a delay used to lengthen
    /// the animation, and normal launches finish in a fraction of this value.
    private static let stepTimeout: TimeInterval = 20

    private var steps: [StartupStep] = []
    private var nextStep = 0
    private var hasStarted = false
    private var isRunning = false
    private var readyObservers: [UUID: () -> Void] = [:]
    private var watchdog: DispatchWorkItem?

    private init() {}

    func start(steps: [StartupStep]) {
        guard !hasStarted else { return }   // foreground returns must never replay boot
        hasStarted = true
        self.steps = steps
        APLog.info("Boot started with \(steps.count) steps", module: "Boot")
        runNextStep()
    }

    func whenServicesReady(_ observer: @escaping () -> Void) -> UUID? {
        guard !servicesReady else {
            observer()
            return nil
        }
        let id = UUID()
        readyObservers[id] = observer
        return id
    }

    func removeServicesReadyObserver(_ id: UUID?) {
        guard let id else { return }
        readyObservers.removeValue(forKey: id)
    }

    func retryStartup() {
        guard errorMessage != nil, !isRunning, nextStep < steps.count else { return }
        errorMessage = nil
        runNextStep()
    }

    func finishDesktopPreparation() {
        guard servicesReady, !desktopReady else { return }
        desktopReady = true
        phase = .ready
        APLog.info("Desktop preparation finished — boot complete", module: "Boot")
    }

    private func runNextStep() {
        guard !isRunning else { return }
        guard nextStep < steps.count else {
            finishServices()
            return
        }

        let stepIndex = nextStep
        let step = steps[stepIndex]
        phase = step.phase
        isRunning = true
        armWatchdog(for: stepIndex)
        let started = Date()
        APLog.info("Boot step started: \(step.phase.title)", module: "Boot")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            do {
                try step.operation()
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                APLog.info("Boot step finished: \(step.phase.title) in \(elapsed) ms", module: "Boot")
                // The watchdog may have failed this step while it was running. Ignore the late
                // completion so a timed-out startup never resumes behind the error screen.
                guard self.nextStep == stepIndex, self.errorMessage == nil else { return }
                self.nextStep += 1
                self.isRunning = false
                self.cancelWatchdog()
                self.runNextStep()
            } catch {
                APLog.error("Boot step failed: \(step.phase.title) — \(error.localizedDescription)", module: "Boot")
                self.fail(error.localizedDescription)
            }
        }
    }

    private func finishServices() {
        cancelWatchdog()
        servicesReady = true
        APLog.info("All boot services ready", module: "Boot")
        if !desktopReady { phase = .preparingDesktop }
        let observers = Array(readyObservers.values)
        readyObservers.removeAll()
        observers.forEach { $0() }
    }

    private func fail(_ message: String) {
        cancelWatchdog()
        isRunning = false
        errorMessage = message
        APLog.error("Boot failed: \(message)", module: "Boot")
        phase = .failed
    }

    /// The watchdog must NOT share the main queue with the work it guards: a step that blocks
    /// the main thread would otherwise silence its own watchdog and strand the user on the boot
    /// screen forever. It now fires on a utility queue, records timestamped evidence immediately,
    /// then hops to main to present the existing retry UI once main is free again.
    private func armWatchdog(for stepIndex: Int) {
        cancelWatchdog()
        let phase = steps[stepIndex].phase
        let timeout = Int(Self.stepTimeout)
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            APLog.fault("Boot step '\(phase.title)' exceeded \(timeout)s; main thread may be blocked",
                        module: "Boot")
            DispatchQueue.main.async {
                guard self.nextStep == stepIndex, !self.servicesReady, self.errorMessage == nil else { return }
                self.fail(String(localized: "Startup took too long to respond."))
            }
        }
        watchdog = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.stepTimeout, execute: item)
    }

    private func cancelWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }
}

struct APLiteBootScreen: View {
    @ObservedObject var boot: BootCoordinator
    @State private var logoVisible = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                APLiteDesign.Surface.bootBackground
                RadialGradient(
                    colors: [APLiteDesign.Surface.bootGlow.opacity(0.13), .clear],
                    center: .init(x: 0.5, y: 0.43),
                    startRadius: 2,
                    endRadius: max(geometry.size.width, geometry.size.height) * 0.72
                )

                VStack(spacing: 0) {
                    Spacer(minLength: APLiteDesign.Space.xxl)

                    Image("LaunchMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: APLiteDesign.bootMarkSize, height: APLiteDesign.bootMarkSize)
                        .opacity(logoVisible ? 1 : 0)
                        .scaleEffect(logoVisible ? 1 : 0.94)
                        .accessibilityHidden(true)

                    Text(verbatim: APLite.name)
                        .font(APLiteDesign.Typography.display)
                        .foregroundStyle(APLiteDesign.Surface.primaryText)
                        .padding(.top, APLiteDesign.Space.lg)

                    Text(verbatim: APLite.tagline)
                        .font(APLiteDesign.Typography.body)
                        .foregroundStyle(APLiteDesign.Surface.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, APLiteDesign.Space.xs)

                    Spacer(minLength: 40)

                    if let errorMessage = boot.errorMessage {
                        VStack(spacing: 14) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title3)
                                .foregroundStyle(APLiteColors.orange)
                                .accessibilityHidden(true)
                            Text(String(format: String(localized: "APLite couldn't finish starting: %@"),
                                        errorMessage))
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.82))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                boot.retryStartup()
                            } label: {
                                Label(String(localized: "Retry startup"), systemImage: "arrow.clockwise")
                                    .frame(minHeight: APLiteDesign.touchTarget)
                            }
                            .buttonStyle(APLiteGlassButtonStyle())
                        }
                        .frame(maxWidth: APLiteDesign.bootStatusMaxWidth)
                    } else {
                        VStack(spacing: APLiteDesign.Space.lg) {
                            Text(boot.phase.title)
                                .font(APLiteDesign.Typography.body.weight(.medium))
                                .foregroundStyle(APLiteDesign.Surface.statusText)
                                .contentTransition(.opacity)
                                .accessibilityAddTraits(.updatesFrequently)

                            ProgressView(value: boot.phase.progress)
                                .tint(APLiteDesign.Surface.bootGlow)
                                .frame(width: 168)
                                .accessibilityLabel(String(localized: "Startup progress"))
                                .accessibilityValue(boot.phase.title)
                        }
                    }

                    Spacer(minLength: APLiteDesign.Space.xxl)
                }
                .padding(.horizontal, APLiteDesign.Space.xxxl)
                .padding(.vertical, APLiteDesign.Space.xxl)
                .frame(maxWidth: APLiteDesign.bootContentMaxWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear {
                guard !logoVisible else { return }
                if APLiteAnimation.reduced {
                    logoVisible = true
                } else {
                    withAnimation(.easeOut(duration: 0.5)) { logoVisible = true }
                }
            }
            .animation(APLiteAnimation.gentle, value: boot.phase)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

struct PhoneRootView: View {
    @ObservedObject private var boot = BootCoordinator.shared
    let model: DesktopModel
    @State private var showSurveyCapture = false

    var body: some View {
        Group {
            if boot.servicesReady {
                ControllerView(model: model)
                    .transition(.opacity)
            } else {
                APLiteBootScreen(boot: boot)
                    .transition(.opacity)
            }
        }
        .animation(APLiteAnimation.gentle, value: boot.servicesReady)
        // The external display is a non-interactive scene: a SwiftUI DragGesture there can never
        // receive the iPhone's touches. Present the survey on the interactive phone surface; the
        // capture helper still snapshots the external desktop through ExternalSceneDelegate.
        .onReceive(NotificationCenter.default.publisher(for: .apliteStartBetaSurvey)) { _ in
            guard APLite.isBeta else { return }
            showSurveyCapture = true
        }
        .fullScreenCover(isPresented: $showSurveyCapture) {
            BetaSurveyCaptureView()
        }
    }
}
