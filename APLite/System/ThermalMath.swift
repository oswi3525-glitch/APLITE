import Foundation

/// Direction of the smoothed thermal-pressure index.
enum ThermalTrend: String {
    case rising, steady, falling

    var symbol: String {
        switch self {
        case .rising: return "↑"
        case .falling: return "↓"
        case .steady: return "→"
        }
    }
}

/// Pure, UI-free maths for the thermal readout. iOS exposes only four public thermal states, so this
/// is an *index* derived from them (0…100%) — never a claim of a °C sensor reading.
enum ThermalMath {
    /// Middle of each public band: nominal, fair, serious, critical.
    static let bandTargets: [Double] = [0.12, 0.45, 0.78, 0.96]

    static func targetPressure(rawState: Int) -> Double {
        guard bandTargets.indices.contains(rawState) else { return 0.5 }
        return bandTargets[rawState]
    }

    /// Move part of the way towards the new band instead of jumping between four coarse values.
    static func smooth(current: Double, target: Double, weight: Double = 0.3) -> Double {
        min(1, max(0, current + (target - current) * min(1, max(0, weight))))
    }

    static func trend(from previous: Double, to current: Double) -> ThermalTrend {
        let delta = current - previous
        if delta > 0.025 { return .rising }
        if delta < -0.025 { return .falling }
        return .steady
    }

    static func percent(_ value: Double) -> Int {
        Int((min(max(value, 0), 1) * 100).rounded())
    }

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0s" }
        let total = Int(seconds)
        if total < 60 { return "\(total)s" }
        let minutes = total / 60, rest = total % 60
        if minutes < 60 { return rest == 0 ? "\(minutes)m" : "\(minutes)m \(rest)s" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
