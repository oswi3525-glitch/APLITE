import SwiftUI
import UIKit

/// Only reachable from Settings → System → Technical Diagnostics. This is a read-only view over data
/// APLite already owns; it is NOT an app (no desktop icon, dock item, launcher entry or new scene).
struct TechnicalDiagnosticsView: View {
    @ObservedObject var model: DesktopModel
    @StateObject private var probe = ResponsivenessProbe()
    @State private var findings: [DiagnosticsPolicy.Finding] = []
    @State private var report = ""
    @State private var checkedAt = Date()
    @State private var confirmRepair: DiagnosticsPolicy.Repair?

    var body: some View {
        List {
            Section {
                Text("Internal — APLite only. Only information APLite already owns. iOS does not let an app read other processes or the system log.")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack {
                    LabeledContent("Checked", value: checkedAt.formatted(date: .omitted, time: .shortened))
                    Spacer()
                    Button("Re-check") { recheck() }.buttonStyle(APLiteGlassButtonStyle())
                }
            } header: {
                Text("Overview")
            }

            Section("Likely causes") {
                if findings.isEmpty { Text("No issues detected.").foregroundStyle(.secondary) }
                ForEach(findings, id: \.id) { finding in
                    VStack(alignment: .leading, spacing: 3) {
                        Label(finding.title, systemImage: finding.severity == .critical
                              ? "exclamationmark.octagon" : finding.severity == .warning
                              ? "exclamationmark.triangle" : "info.circle")
                            .foregroundStyle(finding.severity == .info ? .secondary : APLiteColors.orange)
                        Text(finding.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Repair actions") {
                Text("Actions only touch APLite-owned data and ask for confirmation first.")
                    .font(.footnote).foregroundStyle(.secondary)
                repairButton("Release caches", .releaseCaches)
                repairButton("Discard background tabs", .discardTabs)
                repairButton("Restore audio session", .restoreAudio)
                repairButton("Clear audio event log", .clearAudioLog)
                repairButton("Tile windows", .tileWindows)
                Button("Close all windows", role: .destructive) { confirmRepair = .closeWindows }
                Button("Clear guest caches on next launch") { confirmRepair = .clearGuestCaches }
            }

            Section("Report") {
                Text(DiagnosticsPolicy.truncate(report, limit: 1800))
                    .font(.footnote.monospaced()).textSelection(.enabled)
                Button("Copy report") { UIPasteboard.general.string = report }
                Button("Save a full report") {
                    if APLiteFileManager.writeDiagnostics() != nil {
                        model.showToast(String(localized: "Report saved in APLite's file area."))
                    }
                }
            }
        }
        .navigationTitle("Technical Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { probe.start(); recheck() }
        .onDisappear { probe.stop() }
        .alert("Confirm repair", isPresented: Binding(get: { confirmRepair != nil },
                                                     set: { if !$0 { confirmRepair = nil } })) {
            Button("Cancel", role: .cancel) { confirmRepair = nil }
            Button("Run", role: .destructive) { if let repair = confirmRepair { run(repair) } }
        } message: {
            Text(confirmRepair == .closeWindows
                 ? "This closes all open pages. Unsaved page state may be lost."
                 : "This only changes APLite-owned data. Re-check afterwards to see the result.")
        }
    }

    private func repairButton(_ title: String, _ repair: DiagnosticsPolicy.Repair) -> some View {
        Button(title) { run(repair) }
    }

    private func recheck() {
        let windows = model.windows
        let tabs = windows.reduce(0) { $0 + $1.tabs.count }
        let back = windows.reduce(0) { $0 + $1.tabs.count - (($1.activeTab < $1.tabs.count) ? 1 : 0) }
        let memory = MemoryManager.shared
        let audio = AudioSessionManager.shared
        let audioErrors = audio.events.filter { $0.kind == .error }.count
        let thermal = ThermalMonitor.shared.state.rawValue >= ProcessInfo.ThermalState.fair.rawValue
        let home = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let free = UInt64(max(0, (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? 0))
        findings = DiagnosticsPolicy.findings(
            openWindows: windows.count, tabs: tabs, backgroundTabs: back,
            usedMB: memory.used / (1024 * 1024), peakMB: memory.peak / (1024 * 1024),
            targetMB: memory.targetBytes / (1024 * 1024), suspectedLeak: memory.suspectedLeak,
            thermalWarm: thermal, audioInterrupted: audio.isInterrupted, audioErrors: audioErrors,
            worstUIGap: probe.worstGap, longGaps: probe.longGaps,
            lastCrash: model.crashReport != nil, freeSpaceLow: free > 0 && free < 500_000_000)
        report = DiagnosticsPolicy.redact("""
        APLite technical diagnostics — \(Date().formatted())
        Browser: \(windows.count) windows, \(tabs) tabs, \(back) in background
        Web apps: \(WebApps.shared.all.count), guest apps: \(GuestStore.shared.apps.count)
        Memory: \(memory.report())
        Audio: \(audio.report())
        Thermal: \(ThermalMonitor.shared.detailLines.joined(separator: " | ")); main-thread worst gap: \(String(format: "%.2f", probe.worstGap))s
        \(findings.map { "[\($0.severity.rawValue)] \($0.title): \($0.detail)" }.joined(separator: "\n"))
        """)
        checkedAt = Date()
    }

    private func run(_ repair: DiagnosticsPolicy.Repair) {
        switch repair {
        case .releaseCaches: MemoryManager.shared.releaseCaches(reason: "diagnostics")
        case .discardTabs: for w in model.windows { _ = w.discardBackgroundTabs() }
        case .closeWindows: for w in Array(model.windows) { model.close(w) }
        case .tileWindows: WindowCoordinator.tile()
        case .restoreAudio: AudioSessionManager.shared.activatePlayback(reason: "diagnostics")
        case .clearAudioLog: AudioSessionManager.shared.clearEventLog()
        case .clearGuestCaches: GuestStore.shared.clearCachesOnLaunch = true
        }
        confirmRepair = nil
        MemoryManager.shared.sample()
        recheck()
    }
}

/// 1 Hz main-thread gap sampler, alive only while the diagnostics screen is open.
final class ResponsivenessProbe: ObservableObject {
    @Published private(set) var worstGap: TimeInterval = 0
    @Published private(set) var longGaps = 0
    private var timer: Timer?
    private var lastTick: Date?

    func start() {
        guard timer == nil else { return }
        lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let last = self.lastTick else { return }
            let gap = Date().timeIntervalSince(last)
            self.lastTick = Date()
            if gap > self.worstGap { self.worstGap = gap }
            if gap >= 0.5 { self.longGaps += 1 }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastTick = nil
    }

    deinit { stop() }
}
