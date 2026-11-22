import SwiftUI

/// "Check my setup" on the iPhone: each thing iDesk needs, whether it is there, and in plain words how to fix it.
struct SetupCheckView: View {
    @ObservedObject var model = DesktopModel.shared
    @ObservedObject var devices = MouseInput.shared
    @ObservedObject var store = GuestStore.shared
    @ObservedObject var updates = UpdateChecker.shared
    @Environment(\.dismiss) private var dismiss

    enum State { case ok, warn, info }
    struct Item: Identifiable {
        let id = UUID()
        let state: State
        let title: String
        let detail: String
    }

    private var items: [Item] {
        var list: [Item] = []
        let major = Int(UIDevice.current.systemVersion.split(separator: ".").first ?? "0") ?? 0
        list.append(Item(state: major >= 17 ? .ok : .warn,
                         title: String(localized: "iOS \(UIDevice.current.systemVersion)"),
                         detail: major >= 17 ? String(localized: "APLite needs iOS 17 or later: this iPhone has it.")
                                             : String(localized: "APLite needs iOS 17 or later. Update in Settings → General → Software Update.")))
        if model.isExternalConnected {
            let size = model.screenSize
            list.append(Item(state: .ok, title: String(localized: "Display connected"),
                             detail: RemoteDisplay.shared.isOn ? String(localized: "A laptop shows the desktop in its browser.")
                                 : String(localized: "The desktop is on the display (\(Int(size.width)) × \(Int(size.height))).")))
        } else {
            list.append(Item(state: .warn, title: String(localized: "No display yet"),
                             detail: Device.words(String(localized: "USB-C iPhone: a USB-C → HDMI cable (or a USB-C cable to a monitor with a USB-C video input). Lightning iPhone: Apple's Lightning → HDMI adapter. No cable: Control Center → Screen Mirroring → an Apple TV, an AirPlay TV or a Mac. Laptop: the “Use a laptop as the display” button."))))
        }
        list.append(Item(state: devices.keyboardConnected ? .ok : .info,
                         title: devices.keyboardConnected ? String(localized: "Keyboard connected") : String(localized: "No keyboard"),
                         detail: devices.keyboardConnected ? String(localized: "Typing goes to the desktop.")
                             : String(localized: "Not needed: type in the field at the bottom of the iPhone. A Bluetooth keyboard pairs in Settings → Bluetooth.")))
        list.append(Item(state: devices.mouseConnected ? .ok : .info,
                         title: devices.mouseConnected ? String(localized: "Mouse connected") : String(localized: "No mouse"),
                         detail: devices.mouseConnected ? String(localized: "If the pointer doesn't move, turn on AssistiveTouch: Settings → Accessibility → Touch → AssistiveTouch.")
                             : String(localized: "Not needed: the iPhone is the trackpad. For a mouse, pair it in Settings → Bluetooth with AssistiveTouch on (Accessibility → Touch).")))
        let free = Self.freeSpace
        if free > 0 {
            list.append(Item(state: free < 5 << 30 ? .warn : .ok,
                             title: String(localized: "Free space: \(ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .file))"),
                             detail: free < 5 << 30 ? String(localized: "Below 5 GB: adding and updating apps needs room. Clear the apps' caches on the Apps page, or delete files you don't need.")
                                 : String(localized: "Enough room to add and update apps.")))
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            list.append(Item(state: .warn, title: String(localized: "Low Power Mode is on"),
                             detail: String(localized: "The desktop and apps run slower. Turn it off in Control Center while you work.")))
        }
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        if device.batteryState == .unplugged, device.batteryLevel >= 0, device.batteryLevel < 0.25 {
            list.append(Item(state: .warn, title: String(localized: "Battery \(Int(device.batteryLevel * 100))%"),
                             detail: String(localized: "A USB-C hub with a power port charges the iPhone while it shows the desktop.")))
        }
        if store.apps.contains(where: { !$0.isBundled || $0.hasPendingUpdate }) {
            list.append(Item(state: .warn, title: String(localized: "Apps waiting to be installed"),
                             detail: String(localized: "On the Apps page, tap “Install new apps into APLite” and pick ESign: APLite is signed again with the apps inside.")))
        } else {
            list.append(Item(state: .info, title: String(localized: "\(store.apps.count) iOS apps"),
                             detail: String(localized: "iOS apps come from decrypted IPA files: Apps → Add IPA files. The Apps page lists which apps others got working.")))
        }
        if let app = model.problemApp {
            list.append(Item(state: .warn, title: String(localized: "\(app) closed APLite last time"),
                             detail: String(localized: "Open it on its own, without other heavy apps, and report it from the Apps page if it happens again.")))
        }
        if let r = updates.available {
            list.append(Item(state: .info, title: String(localized: "APLite \(r.version) is available"),
                             detail: String(localized: "Settings → Help → Update: your apps stay.")))
        }
        return list
    }

    private static var freeSpace: UInt64 {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let v = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return UInt64(max(0, v?.volumeAvailableCapacityForImportantUsage ?? 0))
    }

    var body: some View {
        NavigationStack {
            List(items) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.state == .ok ? "checkmark.circle.fill" : item.state == .warn ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(item.state == .ok ? .green : item.state == .warn ? .orange : .blue)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: item.title).font(.headline)
                        Text(verbatim: item.detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Check setup")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
