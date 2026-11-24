import Foundation

/// Pure, testable model for APLite's system log. No OSLog, no file IO, no app singletons —
/// the standalone unit-test target compiles this file directly.
enum APLogLevel: String, Codable, CaseIterable, Equatable {
    case debug
    case info
    case error
    case fault

    var title: String {
        switch self {
        case .debug: return String(localized: "Debug")
        case .info: return String(localized: "Info")
        case .error: return String(localized: "Error")
        case .fault: return String(localized: "Fault")
        }
    }
}

struct APLogEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let level: APLogLevel
    let module: String
    let message: String
}

/// Rotation maths, kept separate from the writer so the cap can be verified without disk IO.
enum APLogRotation {
    static let maxBytes = 512 * 1024
    static let maxRotations = 2

    static func shouldRotate(currentSize: Int, incomingBytes: Int) -> Bool {
        currentSize + incomingBytes > maxBytes
    }

    /// Current file first, then rotations oldest-to-newest.
    static func urls(in directory: URL) -> [URL] {
        var result = [directory.appendingPathComponent("aplite-system.log")]
        for index in 1...maxRotations {
            result.append(directory.appendingPathComponent("aplite-system.\(index).log"))
        }
        return result
    }
}
