import Foundation
import AVFoundation

// MARK: - Diagnostics model

/// One port of the current audio route (speaker, headphones, HDMI, AirPlay, Bluetooth…).
/// Plain strings on purpose: diagnostics stay readable and the formatting can be unit tested.
struct AudioPortSummary: Equatable {
    let portType: String
    let name: String
    let uid: String

    init(portType: String, name: String, uid: String = "") {
        self.portType = portType
        self.name = name
        self.uid = uid
    }

    init(_ port: AVAudioSessionPortDescription) {
        self.portType = port.portType.rawValue
        self.name = port.portName
        self.uid = port.uid
    }

    /// Headphone-like ports, including USB audio adapters (how many iPads reach a display).
    static func isHeadphones(_ portType: String) -> Bool {
        let t = portType.lowercased()
        return t.contains("headphone") || t.contains("headset") || t.contains("usbaudio") || t == "usb"
    }
}

/// A point-in-time picture of the process-wide audio session.
struct AudioSnapshot {
    let category: String
    let mode: String
    let options: [String]
    let isActive: Bool
    let outputVolume: Float
    let sampleRate: Double
    let ioBufferDuration: TimeInterval
    let outputs: [AudioPortSummary]
    let inputs: [AudioPortSummary]
    let timestamp: Date

    var hasHeadphones: Bool {
        outputs.contains { AudioPortSummary.isHeadphones($0.portType) } || inputs.contains { AudioPortSummary.isHeadphones($0.portType) }
    }

    var hasBluetooth: Bool {
        (outputs + inputs).contains { $0.portType.localizedCaseInsensitiveContains("bluetooth") }
    }

    var hasHDMI: Bool { outputs.contains { $0.portType == "HDMI" } }        // AVAudioSessionPortHDMI
    var hasAirPlay: Bool { outputs.contains { $0.portType == "AirPlay" } }  // AVAudioSessionPortAirPlay
    var hasBuiltInSpeaker: Bool { outputs.contains { $0.portType == "BuiltInSpeaker" } }

    var routeDescription: String {
        outputs.isEmpty ? "none" : outputs.map { "\($0.name) (\($0.portType))" }.joined(separator: ", ")
    }

    func report(preamble: String) -> String {
        let date = Self.formatter.string(from: timestamp)
        let optionList = options.isEmpty ? "none" : options.joined(separator: ", ")
        let yes = "yes", no = "no"
        return """
        \(preamble) — \(date)
        Category: \(category)   Mode: \(mode)
        Options: \(optionList)
        Active: \(isActive ? yes : no)   Volume: \(String(format: "%.2f", outputVolume))
        Sample rate: \(String(format: "%.0f", sampleRate)) Hz   I/O buffer: \(String(format: "%.3f", ioBufferDuration)) s
        Output: \(routeDescription)
        Input: \(inputs.isEmpty ? "none" : inputs.map { "\($0.name) (\($0.portType))" }.joined(separator: ", "))
        Devices: built-in speaker=\(hasBuiltInSpeaker ? yes : no) headphones=\(hasHeadphones ? yes : no) \
        Bluetooth=\(hasBluetooth ? yes : no) HDMI=\(hasHDMI ? yes : no) AirPlay=\(hasAirPlay ? yes : no)
        """
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()
}

enum AudioEventKind: String {
    case lifecycle, playback, recording, interruption, route, diagnostic, error
}

struct AudioEvent: Identifiable, Equatable {
    let id: UUID
    let time: Date
    let kind: AudioEventKind
    let message: String

    init(kind: AudioEventKind, message: String, time: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.time = time
        self.kind = kind
        self.message = message
    }

    var line: String {
        let h = Self.timeFormatter.string(from: time)
        return "\(h) [\(kind.rawValue)] \(message)"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()
}

/// Bounded log of audio events — never grows without limit, so diagnostics cannot leak memory.
struct AudioEventLog {
    private(set) var events: [AudioEvent] = []
    let limit: Int

    init(limit: Int = 80) { self.limit = max(1, limit) }

    mutating func append(_ event: AudioEvent) {
        events.append(event)
        if events.count > limit { events.removeFirst(events.count - limit) }
    }

    mutating func clear() { events.removeAll(keepingCapacity: false) }
}
