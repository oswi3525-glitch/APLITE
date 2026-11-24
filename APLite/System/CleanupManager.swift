import Foundation

/// A scan result for one category of APLite-owned junk.
struct CleanupTarget: Identifiable, Equatable {
    let category: CleanupPolicy.Category
    let urls: [URL]
    let bytes: UInt64

    var id: String { category.rawValue }
    var title: String { category.title }
}

/// Scans and deletes ONLY files inside APLite's own sandbox. It never enumerates other apps'
/// containers and never claims to clean the iOS system.
enum CleanupManager {
    private static let fm = FileManager.default
    private static let staleDays = 7
    private static let scanQueue = DispatchQueue(label: "com.hieuk.aplite.cleanup.scan", qos: .utility)

    /// UI entry point: recursive size walks over many-GB guest caches must never run on main.
    static func scan(completion: @escaping ([CleanupTarget]) -> Void) {
        scanQueue.async {
            let result = scan()
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func scan() -> [CleanupTarget] {
        var grouped: [CleanupPolicy.Category: [URL]] = [:]
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let temporary = fm.temporaryDirectory
        let root = APLiteFileManager.systemRoot

        var candidates: [(url: URL, ageChecked: Bool)] = []
        for url in contents(of: caches) { candidates.append((url, false)) }
        for url in contents(of: temporary) { candidates.append((url, true)) }
        for url in contents(of: root) { candidates.append((url, true)) }
        for url in contents(of: root.appendingPathComponent("Logs", isDirectory: true)) { candidates.append((url, true)) }

        for candidate in candidates {
            guard let category = CleanupPolicy.category(for: candidate.url) else { continue }
            // The live log is never a cleanup target; only its numbered rotations are.
            if category == .oldLogs && candidate.url.lastPathComponent == "aplite-system.log" { continue }
            if candidate.ageChecked && !CleanupPolicy.isExpired(modifiedDate(of: candidate.url), days: staleDays) { continue }
            grouped[category, default: []].append(candidate.url)
        }

        // If the web-app registry failed to decode, WebApps.shared.all is empty — treating every
        // icon as orphan would destroy the icons of apps that are actually installed.
        if !WebApps.shared.all.isEmpty {
            let orphanIcons = orphanWebAppIcons()
            if !orphanIcons.isEmpty { grouped[.orphanWebAppIcons] = orphanIcons }
        }

        return grouped
            .map { CleanupTarget(category: $0.key, urls: $0.value, bytes: totalSize(of: $0.value)) }
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
    }

    @discardableResult
    static func remove(_ targets: [CleanupTarget], completion: @escaping (UInt64) -> Void) -> UInt64 {
        let urls = targets.flatMap(\.urls)
        let bytes = targets.reduce(0) { $0 + $1.bytes }
        APLog.info("Cleanup started: \(targets.count) categories, \(urls.count) items, \(bytes) bytes", module: "Cleanup")
        DispatchQueue.global(qos: .utility).async {
            for url in urls { try? fm.removeItem(at: url) }
            APLog.info("Cleanup finished: removed \(urls.count) APLite-owned items", module: "Cleanup")
            DispatchQueue.main.async { completion(bytes) }
        }
        return bytes
    }

    // MARK: - Internals

    private static func contents(of directory: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                     options: [.skipsHiddenFiles])) ?? []
    }

    private static func modifiedDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private static func totalSize(of urls: [URL]) -> UInt64 {
        urls.reduce(0) { total, url in
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return total + (isFolder ? APLiteFileManager.folderSize(of: url) :
                UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
        }
    }

    private static func orphanWebAppIcons() -> [URL] {
        let folder = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WebApps", isDirectory: true)
        let referenced = Set(WebApps.shared.all.map { iconName(for: $0.url) })
        return contents(of: folder).filter { url in
            url.pathExtension.lowercased() == "png" && !referenced.contains(url.deletingPathExtension().lastPathComponent)
        }
    }

    /// Same FNV-1a name WebFeatures uses, so an icon is only removed when truly unreferenced.
    private static func iconName(for url: String) -> String {
        String(url.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }, radix: 16)
    }
}
