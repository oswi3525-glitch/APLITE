import Foundation
import UIKit

/// A small wrapper around iOS's public thermal-pressure API.
///
/// iOS does not expose an exact CPU/battery temperature in °C to third-party apps. `ProcessInfo.thermalState`
/// is the supported signal (nominal → fair → serious → critical); this module turns it into a stable
/// 0…1 level plus a label for the tray and quick panel. No private IOKit calls, no polling storm.
final class ThermalMonitor: ObservableObject {
    static let shared = ThermalMonitor()

    @Published private(set) var state: ProcessInfo.ThermalState = .nominal
    @Published private(set) var level: Double = 0
    @Published private(set) var batteryLevel: Float = -1

    private var timer: Timer?
    private var observer: NSObjectProtocol?

    private init() {}

    deinit {
        timer?.invalidate()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func start() {
        update()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.update() }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.update() }
    }

    func update() {
        let state = ProcessInfo.processInfo.thermalState
        let battery = UIDevice.current.batteryLevel
        if state != self.state || abs(battery - batteryLevel) > 0.01 {
            self.state = state
            self.batteryLevel = battery
            level = Self.level(for: state)
        }
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
