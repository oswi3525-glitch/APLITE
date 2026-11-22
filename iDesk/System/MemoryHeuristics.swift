import Foundation

/// Pure memory heuristics, kept separate from UIKit/AVFoundation so they can be unit tested.
enum MemoryHeuristics {
    /// A long, steady climb with no meaningful drop is suspicious — a *hint*, never proof: a big
    /// download or many open tabs look the same. Requires eight samples (40 s at a 5 s interval).
    static func looksLikeLeak(_ values: [UInt64], minimumGrowthMB: UInt64 = 48) -> Bool {
        guard values.count >= 8 else { return false }
        let recent = Array(values.suffix(8))
        guard let first = recent.first, let last = recent.last, last > first else { return false }
        guard last - first >= minimumGrowthMB * 1024 * 1024 else { return false }
        var dips = 0
        for i in 1..<recent.count where recent[i] < recent[i - 1] { dips += 1 }
        return dips <= 1
    }
}
