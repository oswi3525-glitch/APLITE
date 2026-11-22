import Foundation

/// The Trash of Files: deleted files and folders go to Downloads/.Trash (hidden from Files itself) and can be put
/// back where they were; "Empty Trash", or deleting from inside it, removes them for good.
enum Trash {
    static let folder = ".Trash"
    private static let key = "iDesk.trashOrigins"     // name in the Trash → path it came from

    static var url: URL {
        let url = FileStore.downloads.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var origins: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func isInside(_ path: String) -> Bool { path == folder || path.hasPrefix(folder + "/") }

    static var count: Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).filter { !$0.hasPrefix(".") }.count
    }

    /// Moves files of Files to the Trash; returns how many went there.
    @discardableResult
    static func move(_ paths: [String]) -> Int {
        var moved = 0, all = origins
        for path in paths where !isInside(path) {
            guard let file = FileStore.resolve(path), file != FileStore.downloads.standardizedFileURL else { continue }
            let target = FileStore.uniqueURL(in: url, name: file.lastPathComponent)
            if (try? FileManager.default.moveItem(at: file, to: target)) != nil {
                all[target.lastPathComponent] = path
                moved += 1
            }
        }
        origins = all
        return moved
    }

    /// Puts items of the Trash back where they were (or at the top of Files when that folder is gone).
    static func restore(_ paths: [String]) -> Int {
        var restored = 0, all = origins
        for path in paths where isInside(path) {
            guard let file = FileStore.resolve(path) else { continue }
            let name = file.lastPathComponent
            let origin = all[name] ?? name
            let parentPath = (origin as NSString).deletingLastPathComponent
            let parent = FileStore.resolve(parentPath).flatMap { FileStore.isFolder($0) ? $0 : nil } ?? FileStore.downloads
            let target = FileStore.uniqueURL(in: parent, name: (origin as NSString).lastPathComponent)
            if (try? FileManager.default.moveItem(at: file, to: target)) != nil {
                all[name] = nil
                restored += 1
            }
        }
        origins = all
        return restored
    }

    static func deleteForever(_ paths: [String]) {
        var all = origins
        for path in paths where isInside(path) && path != folder {
            guard let file = FileStore.resolve(path) else { continue }
            try? FileManager.default.removeItem(at: file)
            all[file.lastPathComponent] = nil
        }
        origins = all
    }

    static func empty() {
        let fm = FileManager.default
        for item in (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: item) }
        origins = [:]
    }

    /// Where an item of the Trash came from, for the Files page.
    static func origin(of name: String) -> String? { origins[name] }
}

/// "Compress": the selected files and folders into one .zip next to them.
enum Compressor {
    static func zip(_ paths: [String], in folder: String, completion: @escaping (Result<URL, Error>) -> Void) {
        let files = paths.compactMap(FileStore.resolve)
        guard !files.isEmpty, let parent = FileStore.resolve(folder) else { return }
        let name = files.count == 1 ? files[0].deletingPathExtension().lastPathComponent + ".zip" : String(localized: "Archive") + ".zip"
        let target = FileStore.uniqueURL(in: parent, name: name)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () -> URL in
                let writer = try ZipWriter(creating: target)
                for file in files {
                    if FileStore.isFolder(file) {
                        try writer.addDirectory(file, as: file.lastPathComponent)
                    } else {
                        try writer.addEntry(name: file.lastPathComponent, file: file, mode: 0o644)
                    }
                }
                try writer.finish()
                return target
            }
            if case .failure = result { try? FileManager.default.removeItem(at: target) }
            DispatchQueue.main.async { completion(result) }
        }
    }
}

/// Finds files whose text contains what is typed (text, Markdown, CSV, JSON, HTML, code…), anywhere in Files.
enum ContentSearch {
    static let textExtensions: Set<String> = ["txt", "md", "markdown", "csv", "tsv", "json", "xml", "html", "htm", "css", "js",
                                               "swift", "py", "c", "h", "m", "java", "kt", "sh", "yml", "yaml", "log", "ini", "rtf", "tex"]

    /// Paths of Files whose text contains `query` (case and accents ignored), up to `limit`, with a line around it.
    static func search(_ query: String, limit: Int = 30) -> [(path: String, line: String)] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, let walker = FileManager.default.enumerator(at: FileStore.downloads, includingPropertiesForKeys: [.fileSizeKey],
                                                                         options: [.skipsHiddenFiles]) else { return [] }
        var found: [(String, String)] = []
        for case let url as URL in walker {
            guard textExtensions.contains(url.pathExtension.lowercased()),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 2_000_000,
                  let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)),
                  let r = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]),
                  let path = FileStore.relativePath(of: url) else { continue }
            let lineRange = text.lineRange(for: r)
            var line = text[lineRange].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.count > 120 { line = String(line.prefix(120)) + "…" }
            found.append((path, line))
            if found.count >= limit { break }
        }
        return found
    }
}
