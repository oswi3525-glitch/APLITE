import Foundation
import SwiftUI
import os.log

/// Memory supervision for the whole APLite process. Guest apps run inside this process, so their
/// footprint is included; iOS does not expose a per-guest value and this module does not pretend to.
/// The 1 GB figure is a **management target**, not a cap iOS lets us enforce.
final class MemoryManager: ObservableObject {
    static let shared = MemoryManager()

    @Published private(set) var used: UInt64 = 0
    @Published private(set) var peak: UInt64 = 0
    @Published private(set) var available: UInt64 = 0
    @Published private(set) var warning = false
    @Published private(set) var suspectedLeak = false
    @Published private(set) var samples: [UInt64] = []
    @Published private(set) var lastRelease = Date.distantPast

    private var timer: Timer?
    private let log = OSLog(subsystem: "com.hieuk.aplite", category: "Memory")
    private let maxSamples = 24
    private let historyLimit = 80

    private init() {}

    var targetBytes: UInt64 { UInt64(APLiteSettings.Performance.memoryTargetMB) * 1024 * 1024 }
    var usedFraction: Double { targetBytes > 0 ? min(1, Double(used) / Double(targetBytes)) : 0 }
    var warningThreshold: Double { Double(APLiteSettings.Performance.warningPercent) / 100 }

    /// Sample every 5 seconds. Cheap enough to run while idle; no per-frame work.
    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.sample() }
        timer?.tolerance = 1
    }

    func stop() { timer?.invalidate(); timer = nil }

    func sample() {
        let current = MemoryStatus.used
        let left = MemoryStatus.available
        DispatchQueue.main.async {
            self.used = current
            self.available = left
            self.peak = max(self.peak, current)
            self.samples.append(current)
            if self.samples.count > self.maxSamples { self.samples.removeFirst(self.samples.count - self.maxSamples) }
            self.warning = self.usedFraction >= self.warningThreshold
            self.suspectedLeak = APLiteSettings.Performance.detectLeaks ? self.looksLikeLeak(self.samples) : false
            if self.suspectedLeak {
                os_log("[APLiteMemory] sustained growth — possible leak (used=%{public}llu)", log: self.log, type: .info, current)
            }
            if left > 0 && left < 300 << 20 { self.handlePressure() }
        }
    }

    private func looksLikeLeak(_ values: [UInt64]) -> Bool { MemoryHeuristics.looksLikeLeak(values) }

    /// Releases only caches we own; never user documents or the clipboard.
    func releaseCaches(reason: String) {
        DispatchQueue.main.async {
            URLCache.shared.removeAllCachedResponses()
            QuickLook.stop()
            QuickLook.clearImageCache()
            self.lastRelease = Date()
            os_log("[APLiteMemory] caches released (%{public}s)", log: self.log, type: .info, reason)
        }
    }

    private func handlePressure() {
        guard Date().timeIntervalSince(lastRelease) > 20 else { return }
        releaseCaches(reason: "low memory")
        let model = DesktopModel.shared
        let dropped = model.windows.reduce(0) { $0 + $1.discardBackgroundTabs() }
        if dropped > 0 { model.showToast(String(localized: "Memory is low: \(dropped) background tabs were released.")) }
    }

    func report() -> String {
        let usedText = ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .memory)
        let peakText = ByteCountFormatter.string(fromByteCount: Int64(peak), countStyle: .memory)
        let target = ByteCountFormatter.string(fromByteCount: Int64(targetBytes), countStyle: .memory)
        let guests = DesktopModel.shared.windows.filter { $0.guestWindow != nil }.count
        return """
        \(String(localized: "APLite memory"))
        \(String(localized: "In use")): \(usedText)   \(String(localized: "Peak")): \(peakText)
        \(String(localized: "Target")): \(target)   \(String(localized: "Available")): \(ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .memory))
        \(String(localized: "Guest apps in windows")): \(guests)   \(String(localized: "Possible leak")): \(suspectedLeak ? String(localized: "yes") : String(localized: "no"))
        """
    }
}
