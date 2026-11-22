import Foundation

/// APLite's own file area and file maths. Everything stays inside this app's sandbox
/// (Application Support/APLite and Documents/Downloads); no other app's container is touched.
enum APLiteFileManager {
    /// APLite-managed files: diagnostics, settings exports and build artifacts.
    static var systemRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("APLite", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    struct Metadata {
        let size: Int64
        let modified: Date?
        let created: Date?
        let isFolder: Bool
        let kind: String

        var summary: String {
            let date = modified.map { Self.dateFormatter.string(from: $0) } ?? String(localized: "unknown date")
            return "\(kind) · \(Self.sizeText(size)) · \(date)"
        }

        private static let dateFormatter: DateFormatter = {
            let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
        }()
    }

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Metadata without following symlinks out of the sandbox (iOS app containers have none,
    /// but the guard keeps the API safe if that changes).
    static func metadata(of url: URL) -> Metadata {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .creationDateKey, .isDirectoryKey]
        let values = try? url.resourceValues(forKeys: keys)
        let isDir = values?.isDirectory == true
        return Metadata(size: isDir ? Int64(folderSize(of: url)) : Int64(values?.fileSize ?? 0),
                        modified: values?.contentModificationDate,
                        created: values?.creationDate,
                        isFolder: isDir,
                        kind: kind(of: url, isFolder: isDir))
    }

    /// Recursive size of a folder. The visited set prevents cycles if a symlink ever appears.
    static func folderSize(of url: URL) -> UInt64 {
        var visited = Set<String>()
        return folderSize(of: url, visited: &visited)
    }

    private static func folderSize(of url: URL, visited: inout Set<String>) -> UInt64 {
        let path = url.standardizedFileURL.path
        guard visited.insert(path).inserted else { return 0 }
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys),
                                                    options: [.skipsHiddenFiles])) ?? []
        return children.reduce(0) { total, child in
            let values = try? child.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true { return total }
            if values?.isDirectory == true { return total + folderSize(of: child, visited: &visited) }
            return total + UInt64(values?.fileSize ?? 0)
        }
    }

    private static func kind(of url: URL, isFolder: Bool) -> String {
        if isFolder { return String(localized: "Folder") }
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "gif", "webp": return String(localized: "Image")
        case "mp4", "mov", "m4v", "webm": return String(localized: "Video")
        case "mp3", "m4a", "wav", "aac", "flac": return String(localized: "Audio")
        case "pdf": return String(localized: "PDF document")
        case "ipa": return String(localized: "iOS app")
        case "p12", "pfx": return String(localized: "Certificate")
        case "txt", "md", "json", "csv", "log": return String(localized: "Text")
        default: return String(localized: "File")
        }
    }

    /// Total space used by APLite's own managed area.
    static func systemUsage() -> (files: Int, bytes: UInt64) {
        let fm = FileManager.default
        let children = (try? fm.contentsOfDirectory(at: systemRoot, includingPropertiesForKeys: nil,
                                                    options: [])) ?? []
        return (children.count, folderSize(of: systemRoot))
    }

    /// Writes a real diagnostics report into the APLite area and returns its URL.
    @discardableResult
    static func writeDiagnostics() -> URL? {
        let text = [
            "APLite system diagnostics",
            "Generated: \(Date())",
            "",
            AudioSessionManager.shared.report(),
            "",
            MemoryManager.shared.report(),
            "",
            APLite.attribution,
        ].joined(separator: "\n")
        let url = systemRoot.appendingPathComponent("diagnostics-\(Self.fileStamp()).txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func fileStamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: Date())
    }

    typealias SortKey = FileSorting.Key
    typealias Sortable = FileSorting.Sortable

    static func sorted(_ items: [Sortable], by key: SortKey, ascending: Bool) -> [Sortable] {
        FileSorting.sorted(items, by: key, ascending: ascending)
    }
}
