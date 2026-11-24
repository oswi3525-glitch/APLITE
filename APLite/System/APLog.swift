import Foundation
import os

/// APLite's own, user-visible system log.
///
/// Dual-write by design: structured entries go to Apple Unified Logging (`os_log`, type-safe and
/// privacy-redacted) and, in parallel, to a small rotated JSON-lines file inside APLite's sandbox
/// so the user can read and export them. This never uses the private `OSLogStore` API and never
/// reads another process's log — iOS forbids both.
///
/// Writes hop to a dedicated serial, utility-quality queue for file work, so logging cannot stall
/// boot or the desktop main thread.
enum APLog {
    static let subsystem = "com.hieuk.aplite"

    private static let log = OSLog(subsystem: subsystem, category: "SystemLog")
    private static let queue = DispatchQueue(label: "\(subsystem).systemlog", qos: .utility)
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Public API

    static func debug(_ message: String, module: String = "APLite") {
        write(.debug, module: module, message: message)
    }

    static func info(_ message: String, module: String = "APLite") {
        write(.info, module: module, message: message)
    }

    static func error(_ message: String, module: String = "APLite") {
        write(.error, module: module, message: message)
    }

    static func fault(_ message: String, module: String = "APLite") {
        write(.fault, module: module, message: message)
    }

    /// Snapshot for the in-app log viewer. Newest first. Synchronous only for structured export.
    static func entries() -> [APLogEntry] {
        queue.sync { loadEntries() }
    }

    /// UI entry point: decodes up to ~1.5 MB of rotated JSONL off main, then delivers on main.
    static func entries(completion: @escaping ([APLogEntry]) -> Void) {
        queue.async {
            let all = loadEntries()
            DispatchQueue.main.async { completion(all) }
        }
    }

    /// Pure in-memory filter so the viewer can switch levels without touching disk.
    static func filter(_ entries: [APLogEntry], level: APLogLevel?) -> [APLogEntry] {
        guard let level else { return entries }
        return entries.filter { $0.level == level }
    }

    /// Removes the persisted copy. Unified-log entries are system-managed and cannot be deleted by
    /// a third-party app; only APLite's own file is cleared here.
    static func clear() {
        queue.async {
            for url in APLogRotation.urls(in: logDirectory()) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Structured export for beta surveys and diagnostics. Every message is already redacted by
    /// `DiagnosticsPolicy` before it reaches disk.
    static func exportData() -> Data {
        let all = entries()
        return (try? encoder.encode(all)) ?? Data()
    }

    // MARK: - Internals

    private static func write(_ level: APLogLevel, module: String, message: String) {
        let safeMessage = DiagnosticsPolicy.truncate(DiagnosticsPolicy.redact(message))
        let entry = APLogEntry(id: UUID(), timestamp: Date(), level: level, module: module, message: safeMessage)
        let line = (try? encoder.encode(entry)).flatMap { String(data: $0, encoding: .utf8) }
        let rendered = "[\(module)] \(safeMessage)"

        os_log("%{public}s", log: log, type: level.osLogType, rendered)
        guard let line else { return }
        queue.async { append(line) }
    }

    private static func logDirectory() -> URL {
        let url = APLiteFileManager.systemRoot.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func append(_ line: String) {
        let fm = FileManager.default
        let urls = APLogRotation.urls(in: logDirectory())
        let current = urls[0]
        let size = (try? current.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        if APLogRotation.shouldRotate(currentSize: size, incomingBytes: line.utf8.count + 1) {
            for index in stride(from: APLogRotation.maxRotations, to: 1, by: -1) {
                let destination = urls[index]
                let source = urls[index - 1]
                try? fm.removeItem(at: destination)
                if fm.fileExists(atPath: source.path) {
                    try? fm.moveItem(at: source, to: destination)
                }
            }
            try? fm.removeItem(at: current)
        }

        var data = (try? Data(contentsOf: current)) ?? Data()
        guard let addition = (line + "\n").data(using: .utf8) else { return }
        data.append(addition)
        try? data.write(to: current, options: [.atomic, .completeFileProtectionAfterFirstOpen])
    }

    private static func loadEntries() -> [APLogEntry] {
        var result: [APLogEntry] = []
        for url in APLogRotation.urls(in: logDirectory()) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = line.data(using: .utf8),
                      let entry = try? decoder.decode(APLogEntry.self, from: data) else { continue }
                result.append(entry)
            }
        }
        return result.sorted { $0.timestamp > $1.timestamp }
    }
}

extension APLogLevel {
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .error: return .error
        case .fault: return .fault
        }
    }
}
