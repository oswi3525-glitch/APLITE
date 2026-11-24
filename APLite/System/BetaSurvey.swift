import Foundation
import UIKit

extension Notification.Name {
    /// Posted by the beta-only four-finger hold; observed by the desktop view.
    static let apliteStartBetaSurvey = Notification.Name("APLite.startBetaSurvey")
}

/// A saved beta survey record. Images travel inside the JSON export as base64 (Codable `Data`),
/// so one file is enough for an AI to read the note, the metadata and the screenshot together.
struct SurveyRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let note: String
    let imageData: Data
    let metadata: Metadata

    struct Metadata: Codable, Equatable {
        let deviceModel: String
        let systemVersion: String
        let appVersion: String
        let channel: String
        let thermalState: String
        let lowPowerMode: Bool
        let screenSize: String
    }
}

/// Beta-only survey store. Never called from stable builds: every entry point checks `APLite.isBeta`.
enum BetaSurvey {
    private static let maximumRecords = 12

    private static var storeURL: URL {
        let folder = APLiteFileManager.systemRoot.appendingPathComponent("Surveys", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("records.json")
    }

    static func records() -> [SurveyRecord] {
        guard let data = try? Data(contentsOf: storeURL),
              let list = try? decoder.decode([SurveyRecord].self, from: data) else { return [] }
        return list.sorted { $0.timestamp > $1.timestamp }
    }

    @discardableResult
    static func save(image: UIImage, note: String) -> SurveyRecord? {
        guard let data = normalizedPNG(image) else { return nil }
        // The export is shared outside APLite; never carry a token/password typed into the note.
        let record = SurveyRecord(id: UUID(), timestamp: Date(),
                                  note: DiagnosticsPolicy.redact(note), imageData: data,
                                  metadata: currentMetadata())
        var all = records()
        all.insert(record, at: 0)
        let capped = Array(all.prefix(maximumRecords))
        guard let encoded = try? encoder.encode(capped) else { return nil }
        try? encoded.write(to: storeURL, options: .atomic)
        APLog.info("Beta survey saved (\(data.count) bytes, note length \(note.count))", module: "Survey")
        return record
    }

    static func clear() {
        try? FileManager.default.removeItem(at: storeURL)
        APLog.info("Beta surveys cleared", module: "Survey")
    }

    /// A single structured JSON file ready to share to Files / iCloud Drive and hand to an AI.
    static func exportURL() -> URL? {
        let payload = Payload(
            schema: "aplite.beta-survey.v1",
            hint: "Each record contains a screenshot (base64 PNG), the user's note, timestamp and device metadata. Use the note and image to locate and reproduce the issue, then write a fix prompt for the agent.",
            exportedAt: Date(),
            app: APLite.displayVersion,
            attribution: APLite.attributionShort,
            records: records()
        )
        guard let data = try? encoder.encode(payload) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aplite-surveys-\(stamp()).json")
        guard (try? data.write(to: url, options: [.atomic, .completeFileProtectionAfterFirstOpen])) != nil else { return nil }
        APLog.info("Exported \(payload.records.count) beta survey(s)", module: "Survey")
        return url
    }

    // MARK: - Internals

    private struct Payload: Codable {
        let schema: String
        let hint: String
        let exportedAt: Date
        let app: String
        let attribution: String
        let records: [SurveyRecord]
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    private static func currentMetadata() -> SurveyRecord.Metadata {
        let process = ProcessInfo.processInfo
        let state: String
        switch process.thermalState {
        case .nominal: state = "nominal"
        case .fair: state = "fair"
        case .serious: state = "serious"
        case .critical: state = "critical"
        @unknown default: state = "unknown"
        }
        return SurveyRecord.Metadata(
            deviceModel: UIDevice.current.model,
            systemVersion: UIDevice.current.systemVersion,
            appVersion: APLite.version,
            channel: APLite.channel.isEmpty ? "stable" : APLite.channel,
            thermalState: state,
            lowPowerMode: process.isLowPowerModeEnabled,
            screenSize: Self.currentScreenSize()
        )
    }

    /// Bounds the export: a full-resolution screenshot of a 4K desktop is not useful in a bug report.
    private static func normalizedPNG(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 1600
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image.pngData() }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.pngData()
    }

    private static func stamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: Date())
    }

    /// Screenshot of the current desktop, taken BEFORE the capture overlay is shown so the overlay
    /// never appears in the picture.
    static func captureDesktopImage() -> UIImage? {
        let view = ExternalSceneDelegate.desktopView ?? keyWindow()
        guard let view, view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
        return renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }

    private static func keyWindow() -> UIView? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    private static func currentScreenSize() -> String {
        let size = ExternalSceneDelegate.desktopView?.bounds.size
            ?? (UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.coordinateSpace.bounds.size)
        guard let size else { return "unknown" }
        return "\(Int(size.width))x\(Int(size.height))"
    }
}
