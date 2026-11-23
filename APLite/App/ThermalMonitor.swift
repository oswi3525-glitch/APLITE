import Foundation
import UIKit

/// Reads iOS's public thermal-pressure signal and turns it into a useful, honest readout.
///
/// iOS does not give third-party apps a CPU or battery temperature in °C. `ProcessInfo.thermalState`
/// is the only public signal (nominal → fair → serious → critical). This module keeps that state but
/// adds a smoothed 0…100% pressure index, its trend, how long the state has lasted, the session peak,
/// battery/charging state and Low Power Mode. The index is a proxy for system pressure — it is never
/// presented as a degrees-Celsius measurement. Sampling is slower when nominal, faster when warm.
final class ThermalMonitor: ObservableObject {
    static let shared = ThermalMonitor()

    @Published private(set) var state: ProcessInfo.ThermalState = .nominal
    /// Legacy coarse level (0…1), kept for existing animation/diagnostics callers.
    @Published private(set) var level: Double = 0
    /// Smoothed thermal-pressure index, 0…1. A proxy, not °C.
    @Published private(set) var pressure: Double = ThermalMath.bandTargets[0]
    @Published private(set) var trend: ThermalTrend = .steady
    @Published private(set) var batteryLevel: Float = -1
    @Published private(set) var batteryState: UIDevice.BatteryState = .unknown
    @Published private(set) var lowPower = false
    @Published private(set) var peakRawState = 0
    @Published private(set) var stateStart = Date()

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastStateRaw = 0

    private init() {}

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryState = UIDevice.current.batteryState
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        update()
        // The state may already be nominal on launch (raw == 0), so `update()` has no band change to
        // react to. Schedule the cadence explicitly or the index would stay frozen at its first value.
        if timer == nil { scheduleTimer() }
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in self?.update() })
        observers.append(center.addObserver(forName: UIDevice.batteryLevelDidChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in self?.update() })
        observers.append(center.addObserver(forName: UIDevice.batteryStateDidChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in self?.update() })
        observers.append(center.addObserver(forName: Notification.Name("NSProcessInfoPowerStateDidChange"),
                                            object: nil, queue: .main) { [weak self] _ in self?.update() })
    }

    /// Faster sampling only while the device is warm; no polling storm when it is cool.
    private func scheduleTimer() {
        timer?.invalidate()
        let interval: TimeInterval = state.rawValue >= ProcessInfo.ThermalState.fair.rawValue ? 5 : 15
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    func update() {
        let info = ProcessInfo.processInfo
        let state = info.thermalState
        let raw = state.rawValue
        let battery = UIDevice.current.batteryLevel
        let charging = UIDevice.current.batteryState
        let low = info.isLowPowerModeEnabled

        let previous = pressure
        // A jump into a hotter band is followed quickly; cooling is eased in more slowly.
        let weight = raw > lastStateRaw ? 0.45 : 0.25
        let next = ThermalMath.smooth(current: previous,
                                      target: ThermalMath.targetPressure(rawState: raw),
                                      weight: weight)

        if raw != lastStateRaw {
            self.state = state
            self.stateStart = Date()
            self.lastStateRaw = raw
            level = Self.level(for: state)
            peakRawState = max(peakRawState, raw)
            scheduleTimer()
        }
        let newTrend = ThermalMath.trend(from: previous, to: next)
        if abs(pressure - next) > 0.005 { pressure = next }
        if trend != newTrend { trend = newTrend }
        if abs(battery - batteryLevel) > 0.01 { batteryLevel = battery }
        if charging != batteryState { batteryState = charging }
        if low != lowPower { lowPower = low }
    }

    private static func level(for state: ProcessInfo.ThermalState) -> Double {
        switch state {
        case .nominal: return 0
        case .fair: return 0.4
        case .serious: return 0.75
        case .critical: return 1
        @unknown default: return 0.5
        }
    }

    // MARK: Readout

    var pressurePercent: Int { ThermalMath.percent(pressure) }
    var trendSymbol: String { trend.symbol }
    var stateAge: TimeInterval { Date().timeIntervalSince(stateStart) }

    /// Compact tray / badge text, e.g. "Warm · 48% ↑".
    var reading: String { "\(label) · \(pressurePercent)% \(trendSymbol)" }

    /// Longer form for diagnostics and settings.
    var detailLines: [String] {
        let battery = batteryLevel >= 0 ? "\(ThermalMath.percent(Double(batteryLevel)))%" : "unavailable"
        return [
            "Pressure index: \(pressurePercent)% \(trendSymbol) (\(trend.rawValue))",
            "State: \(Self.stateName(state.rawValue)) for \(ThermalMath.duration(stateAge))",
            "Peak this session: \(Self.stateName(peakRawState))",
            "Battery: \(battery) · \(chargingText)",
            "Low Power Mode: \(lowPower ? "on" : "off")",
            "Source: public iOS thermal state — an index, not °C"
        ]
    }

    private var chargingText: String {
        switch batteryState {
        case .charging: return "charging"
        case .full: return "full"
        case .unplugged: return "on battery"
        @unknown default: return "unknown"
        }
    }

    private static func stateName(_ raw: Int) -> String {
        switch raw {
        case 0: return "Nominal"
        case 1: return "Fair"
        case 2: return "Serious"
        case 3: return "Critical"
        default: return "Unknown"
        }
    }

    var symbol: String {
        switch state {
        case .critical: return "thermometer.sun.fill"
        case .serious: return "thermometer.high"
        case .fair: return "thermometer.medium"
        default: return "thermometer"
        }
    }

    var label: String {
        switch state {
        case .critical: return String(localized: "Critical heat")
        case .serious: return String(localized: "Device is hot")
        case .fair: return String(localized: "Warm")
        default: return String(localized: "Normal temperature")
        }
    }

    var color: UIColor {
        switch state {
        case .critical: return APLiteColors.redUI
        case .serious: return .systemOrange
        case .fair: return .systemYellow
        default: return .systemGreen
        }
    }
}
