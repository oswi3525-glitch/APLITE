import Foundation
import Network
import os

/// How the iPhone is connected, for the network icon in the taskbar tray.
final class NetworkStatus: ObservableObject {
    enum Kind { case wifi, cellular, wired, other, offline }

    static let shared = NetworkStatus()
    @Published private(set) var kind: Kind = .other
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let kind: Kind
            if path.status != .satisfied { kind = .offline }
            else if path.usesInterfaceType(.wifi) { kind = .wifi }
            else if path.usesInterfaceType(.wiredEthernet) { kind = .wired }
            else if path.usesInterfaceType(.cellular) { kind = .cellular }
            else { kind = .other }
            DispatchQueue.main.async { if self?.kind != kind { self?.kind = kind } }
        }
        monitor.start(queue: DispatchQueue(label: "iDesk.network"))
    }

    var symbol: String {
        switch kind {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .wired: return "cable.connector"
        case .other: return "network"
        case .offline: return "wifi.slash"
        }
    }
}

/// Memory used by iDesk, guest apps included (they all run in its process), and what iOS still allows before it
/// closes iDesk. Shown in the taskbar tray.
enum MemoryStatus {
    static var used: UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// 0 where iOS does not say (the Simulator).
    static var available: UInt64 { UInt64(os_proc_available_memory()) }

    enum Level { case fine, low, critical }

    static var level: Level {
        let left = available
        guard left > 0 else { return .fine }
        return left < 300 << 20 ? .critical : left < 700 << 20 ? .low : .fine
    }

    static func format(_ bytes: UInt64) -> String {
        bytes >= 1 << 30 ? String(format: "%.1f GB", Double(bytes) / Double(1 << 30)) : "\(bytes >> 20) MB"
    }
}
