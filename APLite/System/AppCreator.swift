import Foundation

enum AppCreatorError: LocalizedError {
    case invalidName
    case invalidBundleID
    case writeFailed
    case zipFailed

    var errorDescription: String? {
        switch self {
        case .invalidName: return String(localized: "Give the app a name.")
        case .invalidBundleID: return String(localized: "Use a reverse-domain Bundle ID such as com.example.myapp.")
        case .writeFailed: return String(localized: "The project files could not be written.")
        case .zipFailed: return String(localized: "The project ZIP could not be created.")
        }
    }
}

/// Creates a real, buildable iOS project on the device: source files + XcodeGen spec, zipped into
/// APLite's own file area. It never pretends to compile anything — compilation belongs to the
/// macOS worker in Build Center.
enum AppCreator {
    @discardableResult
    static func create(template: AppTemplate, displayName: String, bundleID: String) throws -> URL {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AppCreatorError.invalidName }
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.contains("."), id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else {
            throw AppCreatorError.invalidBundleID
        }
        let module = AppCreatorTemplates.moduleName(name)
        let files = AppCreatorTemplates.files(template: template, displayName: name, bundleID: id)

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("aplite-app-\(UUID().uuidString)", isDirectory: true)
        let zipURL = APLiteFileManager.systemRoot.appendingPathComponent("\(module)-\(Self.stamp()).zip")
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            for (relative, text) in files {
                let file = work.appendingPathComponent(relative)
                try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: file, atomically: true, encoding: .utf8)
            }
            let zip = try ZipWriter(creating: zipURL)
            try zip.addDirectory(work, as: module)
            try zip.finish()
            try? fm.removeItem(at: work)
            return zipURL
        } catch {
            try? fm.removeItem(at: work)
            try? fm.removeItem(at: zipURL)
            throw AppCreatorError.zipFailed
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: Date())
    }
}
