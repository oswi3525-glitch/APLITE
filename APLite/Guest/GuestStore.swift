import UIKit

/// An app installed into iDesk from an IPA file.
struct GuestApp: Identifiable, Equatable {
    let id: String          // bundle identifier
    let name: String
    let bundleURL: URL
    let icon: UIImage?
    /// Already bundled inside iDesk and signed together with it by a signing app (ESign…): opens right away.
    /// false: just imported, lives in Documents, needs the "install into APLite" step.
    let isBundled: Bool
    /// The copy in Documents is newer than the bundled one (re-imported): the next export replaces it.
    var hasPendingUpdate = false
    /// The user chose to remove it from iDesk: the next reinstall leaves it out.
    var pendingRemoval = false
    /// Size on disk (bytes), including bundled frameworks.
    var size: UInt64 = 0

    static func == (a: GuestApp, b: GuestApp) -> Bool { a.id == b.id && a.bundleURL == b.bundleURL }

    enum Tone: String { case good, warn, bad, muted }

    /// Where the app stands, as the Apps sheet on the iPhone and the Apps page on the desktop show it.
    var status: (text: String, tone: Tone) {
        #if targetEnvironment(simulator)
        return (id, .muted)
        #else
        let size = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        if pendingRemoval { return (String(localized: "Removed when APLite is reinstalled · \(size)"), .bad) }
        if isBundled && !hasPendingUpdate { return (String(localized: "Ready · \(size)"), .good) }
        if GuestStore.canLoadOutsideBundle {
            return SigningStore.shared.identity == nil
                ? (String(localized: "Needs a certificate (Advanced)"), .warn)
                : (String(localized: "Ready (signed on device)"), .good)
        }
        return (String(localized: "Waiting to be installed into APLite · \(size)"), .warn)
        #endif
    }
}

/// The guest app library.
///
/// With a normal certificate iOS only runs code that is part of an installed app, so:
/// 1. Add IPA → unpack, patch the executable, keep it temporarily in Documents/GuestApps.
/// 2. "Install into APLite" → build an IPA = iDesk + the guest apps in iDesk.app/Frameworks.
/// 3. The user signs it with a signing app (ESign…) and installs over iDesk → the guests are properly signed and load.
/// After installing, the temporary copies and the exported file are deleted; apps marked for removal are dropped on the next install.
final class GuestStore: ObservableObject {
    static let shared = GuestStore()

    enum Failure: LocalizedError {
        case noApp
        case badInfo

        var errorDescription: String? {
            switch self {
            case .noApp: return String(localized: "The IPA has no Payload/*.app folder.")
            case .badInfo: return String(localized: "Cannot read the app’s Info.plist.")
            }
        }
    }

    @Published private(set) var apps: [GuestApp] = []
    @Published private(set) var isInstalling = false
    /// Batch install in progress: IPAs finished so far, out of `total`.
    @Published private(set) var installProgress: (done: Int, total: Int)?

    private let root: URL
    private let fm = FileManager.default

    /// iDesk's own bundle (not Bundle.main, which is swapped while a guest app runs).
    private static let ownBundle = URL(fileURLWithPath: OwnSignature.executablePath).deletingLastPathComponent()
    private static let bundledPrefix = "iDeskGuest_"
    private static let exportMarker = "iDeskExport.id"
    /// Frameworks a guest app put into iDesk.app/Frameworks (so they can be removed later).
    private static let frameworkList = "iDeskFrameworks.txt"
    private static let removalKey = "iDesk.pendingRemoval"

    /// Bundled apps the user wants removed on the next reinstall.
    private var pendingRemoval: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.removalKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.removalKey) }
    }

    /// Total size of the apps inside iDesk.
    var totalSize: UInt64 { apps.reduce(0) { $0 + $1.size } }

    /// Whether any app was imported (or updated) and not yet packaged for the signing app.
    var hasPendingExport: Bool { apps.contains { !$0.isBundled || $0.hasPendingUpdate || $0.pendingRemoval } }

    private init() {
        // Stored in Documents like LiveContainer: with get-task-allow, iOS loads signed code from here.
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = documents.appendingPathComponent("GuestApps", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        // Older versions stored apps in Application Support: move them.
        let old = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GuestApps", isDirectory: true)
        for item in (try? fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil)) ?? [] {
            let target = root.appendingPathComponent(item.lastPathComponent)
            if !fm.fileExists(atPath: target.path) { try? fm.moveItem(at: item, to: target) }
        }
        try? fm.removeItem(at: old)
        purgeLeftovers()
        reload()
    }

    // MARK: Space

    /// What an install, export or update cut short (iDesk closed or suspended half-way: the user switched apps or
    /// locked the iPhone) left behind: a whole copy of iDesk and its apps each time, never deleted, so a few
    /// updates added up to tens of gigabytes. Nothing of this is in use when iDesk starts. With "clear caches"
    /// chosen, the apps' caches (Library/Caches: TikTok's videos…) go too, before any app runs again.
    private func purgeLeftovers() {
        let tmp = fm.temporaryDirectory, root = self.root, fm = self.fm
        let clearCaches = UserDefaults.standard.bool(forKey: Self.clearCachesKey)
        UserDefaults.standard.removeObject(forKey: Self.clearCachesKey)
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        if clearCaches {
            for item in (try? fm.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: item) }
        }
        DispatchQueue.global(qos: .utility).async {
            var freed: UInt64 = 0
            let stale = ((try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? [])
                .filter { item in clearCaches || ["export-", "update-"].contains { item.lastPathComponent.hasPrefix($0) } }
                + ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix(".tmp-") }
            for item in stale {
                freed += Self.size(of: item)
                try? fm.removeItem(at: item)
            }
            if freed > 0 { NSLog("[iDesk] removed %llu MB left by unfinished installs and updates", freed / 1_048_576) }
            self.measureCaches()
        }
    }

    private static let clearCachesKey = "iDesk.clearCachesOnLaunch"

    /// The apps' caches in Library/Caches (shared by every app inside iDesk), in bytes; nil until measured.
    @Published private(set) var cachesSize: UInt64?
    var clearCachesOnLaunch: Bool {
        get { UserDefaults.standard.bool(forKey: Self.clearCachesKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.clearCachesKey); objectWillChange.send() }
    }

    func measureCaches() {
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        DispatchQueue.global(qos: .utility).async {
            let size = Self.size(of: caches)
            DispatchQueue.main.async { self.cachesSize = size }
        }
    }

    /// Keeps iDesk running for a while if the user leaves it during a long install or export (iOS would suspend it
    /// at once and could end it, leaving the work half done).
    private static func whileRunning<T>(_ name: String, _ work: () throws -> T) rethrows -> T {
        var task = UIBackgroundTaskIdentifier.invalid
        DispatchQueue.main.sync {
            task = UIApplication.shared.beginBackgroundTask(withName: name) { UIApplication.shared.endBackgroundTask(task) }
        }
        defer { DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(task) } }
        return try work()
    }

    func reload() {
        // Apps already bundled inside iDesk (signed by the signing app).
        let frameworks = Self.ownBundle.appendingPathComponent("Frameworks", isDirectory: true)
        let removal = pendingRemoval
        let bundled = ((try? fm.contentsOfDirectory(at: frameworks, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(Self.bundledPrefix) && $0.pathExtension == "framework" }
            .compactMap { url -> GuestApp? in
                guard var app = Self.describe(url, bundled: true) else { return nil }
                app.pendingRemoval = removal.contains(app.id)
                // Include the frameworks it put into iDesk.app/Frameworks.
                app.size += Self.frameworkNames(of: url).reduce(0) { $0 + Self.size(of: frameworks.appendingPathComponent($1)) }
                return app
            }
        var byID = Dictionary(bundled.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Reinstall done: removed apps are no longer inside iDesk.
        let stillBundled = removal.filter { byID[$0] != nil }
        if stillBundled != removal { pendingRemoval = stillBundled }

        // Newly imported apps in Documents.
        let local = ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "app" }
        for url in local {
            guard let app = Self.describe(url, bundled: false) else { continue }
            if var packaged = byID[app.id] {
                // This copy was packaged in the previous export and the user has reinstalled: delete it to save space.
                if Self.marker(in: url) != nil, Self.marker(in: url) == Self.marker(in: packaged.bundleURL) {
                    try? fm.removeItem(at: url)
                } else {
                    packaged.hasPendingUpdate = true
                    packaged.size += app.size
                    byID[app.id] = packaged
                }
            } else {
                byID[app.id] = app
            }
        }
        apps = byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Nothing waiting to be installed: the exported IPA (almost the size of iDesk) is no longer needed.
        if !hasPendingExport {
            try? fm.removeItem(at: Self.exportFolder)
        }
    }

    private static var exportFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Export", isDirectory: true)
    }

    private static func frameworkNames(of guest: URL) -> [String] {
        ((try? String(contentsOf: guest.appendingPathComponent(frameworkList), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Marks / unmarks a bundled app for removal (applied on the next reinstall).
    func toggleRemoval(_ app: GuestApp) {
        var set = pendingRemoval
        if set.contains(app.id) { set.remove(app.id) } else { set.insert(app.id) }
        pendingRemoval = set
        reload()
    }

    /// An app's copy in Documents (if any), used when exporting.
    private func localCopy(of id: String) -> URL? {
        ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .first { $0.pathExtension == "app" && Self.describe($0, bundled: false)?.id == id }
    }

    private static func marker(in bundle: URL) -> String? {
        try? String(contentsOf: bundle.appendingPathComponent(exportMarker), encoding: .utf8)
    }

    /// The outcome of installing one IPA file.
    struct InstallResult {
        let file: String
        let result: Result<GuestApp, Error>
    }

    /// Installs IPAs one after another on a background queue, then reports every result on the main queue.
    /// One at a time: each unpacks a whole app, and running them together would only compete for disk and memory.
    func install(ipas: [URL], completion: @escaping ([InstallResult]) -> Void) {
        guard !ipas.isEmpty else { return }
        if isInstalling {
            queued.append((ipas, completion))     // more files arrived meanwhile: run them afterwards
            return
        }
        isInstalling = true
        installProgress = (0, ipas.count)
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [InstallResult] = []
            for (index, ipa) in ipas.enumerated() {
                let scoped = ipa.startAccessingSecurityScopedResource()
                results.append(InstallResult(file: ipa.lastPathComponent, result: Result { try Self.whileRunning("iDesk install") { try self.installSync(ipa) } }))
                if scoped { ipa.stopAccessingSecurityScopedResource() }
                // The document picker copied the IPA into iDesk's temporary folder: delete it once unpacked.
                if ipa.standardizedFileURL.path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path) {
                    try? FileManager.default.removeItem(at: ipa)
                }
                DispatchQueue.main.async { self.installProgress = (index + 1, ipas.count) }
            }
            DispatchQueue.main.async {
                self.isInstalling = false
                self.installProgress = nil
                self.reload()
                completion(results)
                if !self.queued.isEmpty {
                    let (more, done) = self.queued.removeFirst()
                    self.install(ipas: more, completion: done)
                }
            }
        }
    }

    private var queued: [([URL], ([InstallResult]) -> Void)] = []

    /// What to tell the user after a batch install. `next` is appended when every IPA was added.
    static func summary(of results: [InstallResult], next: String? = nil) -> String {
        let added = results.compactMap { try? $0.result.get() }
        var lines: [String] = []
        if added.count == 1 {
            lines.append(String(localized: "Added “\(added[0].name)”."))
        } else if !added.isEmpty {
            let names = added.map(\.name).joined(separator: ", ")
            lines.append(String(localized: "Added \(added.count) apps: \(names)."))
        }
        for r in results {
            if case .failure(let error) = r.result {
                lines.append(String(localized: "Could not add \(r.file): \(error.localizedDescription)"))
            }
        }
        if added.count == results.count, let next { lines.append(next) }
        return lines.joined(separator: "\n\n")
    }

    private func installSync(_ ipa: URL) throws -> GuestApp {
        let work = root.appendingPathComponent(".tmp-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }
        try Unzip.extract(ipa, to: work)

        let payload = work.appendingPathComponent("Payload", isDirectory: true)
        let bundles = (try? fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)) ?? []
        guard let bundle = bundles.first(where: { $0.pathExtension == "app" }) else { throw Failure.noApp }
        guard let info = Self.info(of: bundle),
              let id = info["CFBundleIdentifier"] as? String,
              let executable = info["CFBundleExecutable"] as? String else { throw Failure.badInfo }

        try MachOPatcher.patchExecutable(at: bundle.appendingPathComponent(executable))
        Self.weakenMissingImports(in: bundle, executable: executable)
        try Self.sign(bundle, executable: executable, bundleID: id)
        // App extensions (widgets, share…) cannot run inside iDesk.
        for junk in ["PlugIns", "Extensions", "Watch", "SC_Info"] {
            try? fm.removeItem(at: bundle.appendingPathComponent(junk))
        }

        // Re-importing an app marked for removal: cancel the removal.
        var removal = pendingRemoval
        if removal.remove(id) != nil { pendingRemoval = removal }

        let safeName = id.replacingOccurrences(of: "/", with: "_")
        let target = root.appendingPathComponent("\(safeName).app", isDirectory: true)
        try? fm.removeItem(at: target)
        try fm.moveItem(at: bundle, to: target)
        guard let app = Self.describe(target, bundled: false) else { throw Failure.badInfo }
        return app
    }

    // MARK: Export for the signing app

    /// Builds an IPA = iDesk + every guest app (already bundled and newly imported).
    /// The user signs it with ESign (or similar) and installs it over iDesk.
    /// `base`: a newer iDesk.app (an update downloaded from GitHub) to package instead of the running one; the apps
    /// bundled in the running iDesk are carried over into it, so updating iDesk keeps them.
    func exportForESign(base: URL? = nil, progress: @escaping (Double) -> Void,
                        completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Self.whileRunning("iDesk export") { try self.exportSync(base: base, progress: progress) } }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func exportSync(base: URL?, progress: @escaping (Double) -> Void) throws -> URL {
        let own = base ?? Self.ownBundle
        let appName = own.lastPathComponent                     // "APLite.app"
        let payload = "Payload/" + appName
        let exportID = UUID().uuidString
        let work = fm.temporaryDirectory.appendingPathComponent("export-\(exportID)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // Newly imported / updated guest apps (the copies in Documents).
        let pending = ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "app" }
        struct Guest { let source: URL; let folder: String; let executable: String }
        var guests: [Guest] = []
        for url in pending {
            guard let info = Self.info(of: url),
                  let id = info["CFBundleIdentifier"] as? String,
                  let executable = info["CFBundleExecutable"] as? String else { continue }
            let folder = Self.bundledPrefix + id.replacingOccurrences(of: ".", with: "_") + ".framework"
            guests.append(Guest(source: url, folder: folder, executable: executable))
        }

        // What the new guest apps will put into iDesk.app/Frameworks: drop iDesk's old copies with the same names.
        var replacedTop = Set(guests.map(\.folder))
        for g in guests {
            let inner = g.source.appendingPathComponent("Frameworks", isDirectory: true)
            for item in (try? fm.contentsOfDirectory(at: inner, includingPropertiesForKeys: nil)) ?? [] {
                replacedTop.insert(item.lastPathComponent)
            }
        }

        // Bundled apps marked for removal: drop their folder and the frameworks only they use.
        // (Always those of the running iDesk: an update's own bundle has none.)
        let ownFrameworks = Self.ownBundle.appendingPathComponent("Frameworks", isDirectory: true)
        let packaged = ((try? fm.contentsOfDirectory(at: ownFrameworks, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(Self.bundledPrefix) }
        let removal = pendingRemoval
        var removedTop = Set<String>()
        var keptFrameworks = Set<String>()
        for url in packaged {
            let id = (Self.info(of: url)?["CFBundleIdentifier"] as? String) ?? ""
            if removal.contains(id) && !replacedTop.contains(url.lastPathComponent) {
                removedTop.insert(url.lastPathComponent)
                removedTop.formUnion(Self.frameworkNames(of: url))
            } else {
                keptFrameworks.formUnion(Self.frameworkNames(of: url))
            }
        }
        removedTop.subtract(keptFrameworks)
        removedTop.subtract(replacedTop)
        let skippedTop = replacedTop.union(removedTop)
        // Packaging an update: what the running iDesk has in Frameworks for its apps goes into the new one as it is.
        let carried: [URL] = base == nil ? [] : packaged.filter { !skippedTop.contains($0.lastPathComponent) }
        var carriedTop = Set(carried.map(\.lastPathComponent))
        if base != nil {
            for name in keptFrameworks where !skippedTop.contains(name) { carriedTop.insert(name) }
        }

        let carriedSize = carriedTop.reduce(UInt64(0)) { $0 + Self.size(of: ownFrameworks.appendingPathComponent($1)) }
        let total = Double(max(1, Self.size(of: own) + carriedSize + guests.reduce(0) { $0 + Self.size(of: $1.source) }))
        let output = Self.exportFolder
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        let file = output.appendingPathComponent("iDesk-with-apps.ipa")
        try? fm.removeItem(at: file)
        let zip = try ZipWriter(creating: file)
        let report: (UInt64) -> Void = { written in progress(min(1, Double(written) / total)) }

        // 1. iDesk itself (minus old guest apps that get replaced), with the guests' Info.plist needs merged in.
        let ownInfo = work.appendingPathComponent(UUID().uuidString)
        let merged = try Self.mergedInfo(own: own, guests: guests.map(\.source) + carried)
        try merged.data.write(to: ownInfo)
        var ownReplace = ["Info.plist": ownInfo]
        // iDesk's translated permission texts would hide the guest's own wording: drop those keys from them.
        for lproj in ((try? fm.contentsOfDirectory(atPath: own.path)) ?? []) where lproj.hasSuffix(".lproj") {
            let path = lproj + "/InfoPlist.strings"
            guard !merged.guestKeys.isEmpty,
                  let strings = NSMutableDictionary(contentsOf: own.appendingPathComponent(path)) else { continue }
            strings.removeObjects(forKeys: Array(merged.guestKeys))
            let file = work.appendingPathComponent(UUID().uuidString)
            try PropertyListSerialization.data(fromPropertyList: strings, format: .binary, options: 0).write(to: file)
            ownReplace[path] = file
        }
        try zip.addDirectory(own, as: payload, skip: { rel in
            let parts = rel.split(separator: "/", maxSplits: 2).map(String.init)
            return parts.count >= 2 && parts[0] == "Frameworks" && skippedTop.contains(parts[1])
        }, replace: ownReplace, progress: report)

        // 1b. An update: the apps (and their frameworks) of the running iDesk, unchanged.
        for name in carriedTop.sorted() {
            let item = ownFrameworks.appendingPathComponent(name)
            guard fm.fileExists(atPath: item.path) else { continue }
            if FileStore.isFolder(item) {
                try zip.addDirectory(item, as: payload + "/Frameworks/" + name, progress: report)
            } else {
                try zip.addEntry(name: payload + "/Frameworks/" + name, file: item, mode: 0o755)
            }
        }

        // 2. Each guest app.
        var seenTop = carriedTop
        for g in guests {
            let dest = payload + "/Frameworks/" + g.folder

            // Executable: rewrite framework paths for the new layout (frameworks sit next to it, not nested).
            let exe = work.appendingPathComponent(UUID().uuidString)
            try MachOPatcher.relocateFrameworks(from: g.source.appendingPathComponent(g.executable), to: exe)
            // Info.plist: declare it a framework so signing apps and iOS accept it in the Frameworks folder.
            let plist = work.appendingPathComponent(UUID().uuidString)
            if let info = NSMutableDictionary(contentsOf: g.source.appendingPathComponent("Info.plist")) {
                info["CFBundlePackageType"] = "FMWK"
                let data = try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
                try data.write(to: plist)
            }
            let marker = work.appendingPathComponent(UUID().uuidString)
            try exportID.write(to: marker, atomically: true, encoding: .utf8)
            // Record the frameworks it puts into iDesk.app/Frameworks, so they can be removed later.
            let inner = g.source.appendingPathComponent("Frameworks", isDirectory: true)
            let names = ((try? fm.contentsOfDirectory(atPath: inner.path)) ?? []).sorted()
            let list = work.appendingPathComponent(UUID().uuidString)
            try names.joined(separator: "\n").write(to: list, atomically: true, encoding: .utf8)

            try zip.addDirectory(g.source, as: dest, skip: { rel in
                rel == "Frameworks" || rel.hasPrefix("Frameworks/") || rel == "_CodeSignature" || rel.hasPrefix("_CodeSignature/")
                    || rel == "embedded.mobileprovision" || rel == Self.exportMarker || rel == Self.frameworkList
            }, replace: [g.executable: exe, "Info.plist": plist], progress: report)
            try zip.addEntry(name: dest + "/" + Self.exportMarker, file: marker, mode: 0o644)
            try zip.addEntry(name: dest + "/" + Self.frameworkList, file: list, mode: 0o644)

            // The guest's own frameworks → iDesk.app/Frameworks (on a name clash the first one wins).
            for item in (try? fm.contentsOfDirectory(at: inner, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
                let name = item.lastPathComponent
                guard seenTop.insert(name).inserted else { continue }
                if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    try zip.addDirectory(item, as: payload + "/Frameworks/" + name, skip: { rel in
                        rel == "_CodeSignature" || rel.hasPrefix("_CodeSignature/")
                    }, progress: report)
                } else {
                    try zip.addEntry(name: payload + "/Frameworks/" + name, file: item, mode: 0o755)
                }
            }
        }
        try zip.finish()

        // Mark the copies in Documents: after the user reinstalls iDesk, reload() deletes them.
        for g in guests {
            try? exportID.write(to: g.source.appendingPathComponent(Self.exportMarker), atomically: true, encoding: .utf8)
        }
        progress(1)
        return file
    }

    /// iOS reads some settings only from the installed app's Info.plist, i.e. iDesk's, never the guest's:
    /// permission texts, network security (ATS), background modes, URL schemes (sign-in callbacks) and the
    /// schemes an app may query. Copy what the guests declare into iDesk's, so they behave as on their own.
    private static func mergedInfo(own: URL, guests: [URL]) throws -> (data: Data, guestKeys: Set<String>) {
        let info = NSMutableDictionary(contentsOf: own.appendingPathComponent("Info.plist")) ?? NSMutableDictionary()
        var guestKeys = Set<String>()
        func union(_ key: String, _ values: [Any]) {
            var list = (info[key] as? [Any]) ?? []
            for v in values where !list.contains(where: { ($0 as AnyObject).isEqual(v) }) { list.append(v) }
            if !list.isEmpty { info[key] = list }
        }
        for guest in guests {
            guard let g = Self.info(of: guest) as? [String: Any] else { continue }
            for (key, value) in g where key.hasSuffix("UsageDescription") && value is String {
                info[key] = value                                   // the guest's own wording beats iDesk's generic one
                guestKeys.insert(key)
            }
            for key in ["UIBackgroundModes", "LSApplicationQueriesSchemes", "NSBonjourServices", "CFBundleURLTypes"] {
                if let values = g[key] as? [Any] { union(key, values) }
            }
            if let ats = g["NSAppTransportSecurity"] as? [String: Any], !ats.isEmpty {
                // Exceptions are per domain and per app; allowing every load covers whatever the guest relaxed.
                info["NSAppTransportSecurity"] = ["NSAllowsArbitraryLoads": true]
            }
        }
        return (try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0), guestKeys)
    }

    /// A bundle's Info.plist.
    private static func info(of bundle: URL) -> NSDictionary? {
        NSDictionary(contentsOf: bundle.appendingPathComponent("Info.plist"))
    }

    private static func size(of directory: URL) -> UInt64 {
        var total: UInt64 = 0
        let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        while let url = walker?.nextObject() as? URL {
            total += UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// Tweaked apps often bundle old libraries linking removed iOS libraries (libstdc++) or calling removed functions
    /// (e.g. libsubstrate.dylib → _dyld_get_all_image_infos): make those optional so dyld does not refuse to load the
    /// whole app. Checked against the iOS that is running.
    private static func weakenMissingImports(in bundle: URL, executable: String) {
        var files = [bundle.appendingPathComponent(executable)]
        let frameworks = bundle.appendingPathComponent("Frameworks", isDirectory: true)
        if let walker = FileManager.default.enumerator(at: frameworks, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in walker where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                && MachOPatcher.isMachO(url) {
                files.append(url)
            }
        }
        for url in files {
            try? MachOPatcher.thin(at: url)
            // A framework's "@executable_path/Frameworks" (iDesk's folder inside iDesk) → the app's Frameworks.
            let parent = url.deletingLastPathComponent()
            let replacement: String? = parent.standardizedFileURL == frameworks.standardizedFileURL ? "@loader_path"
                : parent.pathExtension == "framework" && parent.deletingLastPathComponent().standardizedFileURL == frameworks.standardizedFileURL
                    ? "@loader_path/.." : nil
            if url != files[0], let replacement, (try? MachOPatcher.pointExecutablePath(at: url, to: replacement)) == true {
                NSLog("[iDesk] %@: its @executable_path now points at the app's Frameworks", url.lastPathComponent)
            }
            if let paths = try? ImportWeakener.weakLinkMissingSystemLibraries(at: url), !paths.isEmpty {
                NSLog("[iDesk] %@: removed libraries replaced by libc++: %@", url.lastPathComponent, paths.joined(separator: ", "))
            }
            if let names = try? ImportWeakener.weakenMissingSystemImports(at: url), !names.isEmpty {
                let shown = names.prefix(40).joined(separator: ", ") + (names.count > 40 ? " … (\(names.count) in all)" : "")
                NSLog("[iDesk] %@: marked weak %@", url.lastPathComponent, shown)
            }
        }
    }

    /// Re-signs a guest app. Simulator: an ad-hoc signature is enough. Device: needs an imported certificate;
    /// without one it still installs, but iOS refuses to load it until a certificate is imported and it is re-signed.
    private static func sign(_ bundle: URL, executable: String, bundleID: String) throws {
        #if targetEnvironment(simulator)
        // Ad-hoc, but every Mach-O: the libraries weakenMissingImports patched need a new signature too.
        try CodeSigner.signBundle(bundle, executable: executable, bundleID: bundleID, identity: nil)
        #else
        guard let identity = SigningStore.shared.identity else { return }
        // Some apps read embedded.mobileprovision from their own bundle (Bundle.main points at the guest).
        if let profile = SigningStore.shared.profile {
            try? profile.data.write(to: bundle.appendingPathComponent("embedded.mobileprovision"))
        }
        try CodeSigner.signBundle(bundle, executable: executable, bundleID: bundleID, identity: identity)
        #endif
    }

    /// Re-signs every installed app (after the user imports or changes the certificate).
    func resignAll() throws {
        for app in apps {
            guard let info = Self.info(of: app.bundleURL),
                  let executable = info["CFBundleExecutable"] as? String else { continue }
            try Self.sign(app.bundleURL, executable: executable, bundleID: app.id)
        }
    }

    /// Checks before loading: iOS only loads libraries signed with the same Team ID as iDesk.
    /// Apps installed before a certificate existed (or signed with an old one) are re-signed right here.
    /// iOS only loads code from outside the bundle (the data container) when iDesk has get-task-allow
    /// (installed with a development certificate). With a normal ESign certificate the app must be bundled into iDesk.
    static var canLoadOutsideBundle: Bool { OwnSignature.getTaskAllow == true }

    /// Opens without asking anything of the user (no install step, no certificate): used to reopen apps by themselves.
    func opensRightAway(_ app: GuestApp) -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return (app.isBundled && !app.hasPendingUpdate) || (Self.canLoadOutsideBundle && SigningStore.shared.identity != nil)
        #endif
    }

    func prepareForLaunch(_ app: GuestApp) throws {
        #if !targetEnvironment(simulator)
        if app.isBundled && !app.hasPendingUpdate { return }   // signed together with iDesk by the signing app
        guard Self.canLoadOutsideBundle else { throw LaunchProblem.needsInstall(app.name) }
        guard let identity = SigningStore.shared.identity else { throw LaunchProblem.noCertificate(app.name) }
        if let own = OwnSignature.teamID, !own.isEmpty, own != identity.teamID {
            throw LaunchProblem.teamMismatch(certificate: identity.teamID, idesk: own)
        }
        guard let info = Self.info(of: app.bundleURL),
              let executable = info["CFBundleExecutable"] as? String else { throw Failure.badInfo }
        let current = EmbeddedSignature(executable: app.bundleURL.appendingPathComponent(executable).path)
        // Re-sign if: different team, ad-hoc, or signed by an old iDesk without the Apple certificate chain.
        if current?.teamID != identity.teamID || current?.isAdhoc != false || (current?.certificates.count ?? 0) < 2 {
            try Self.sign(app.bundleURL, executable: executable, bundleID: app.id)
        }
        #endif
    }

    enum LaunchProblem: LocalizedError {
        case needsInstall(String)
        case noCertificate(String)
        case teamMismatch(certificate: String, idesk: String)

        var errorDescription: String? {
            switch self {
            case .needsInstall(let name):
                return String(localized: "“\(name)” is not installed into APLite yet. iOS only runs code inside an installed app: tap the box button → “Install new apps into APLite”, pick ESign (or your signing app), then sign and install as usual. Reopen APLite and it runs.")
            case .noCertificate(let name):
                return String(localized: "“\(name)” is not signed because APLite has no certificate. Tap the box button → Import certificate and choose the certificate .zip (the one you used to install APLite). You only need to do this once.")
            case let .teamMismatch(cert, idesk):
                return String(localized: "The imported certificate (Team \(cert)) differs from the one signing APLite (Team \(idesk)). iOS only loads apps signed by the same Team as APLite. Re-sign APLite in ESign with this certificate, or import the certificate used to sign APLite.")
            }
        }
    }

    /// Deletes the copy in Documents. A bundled app can only be removed by exporting again without it.
    func remove(_ app: GuestApp) {
        if let local = localCopy(of: app.id) { try? fm.removeItem(at: local) }
        if !app.isBundled { try? fm.removeItem(at: app.bundleURL) }
        reload()
    }

    private static func describe(_ bundle: URL, bundled: Bool) -> GuestApp? {
        guard let info = Self.info(of: bundle),
              let id = info["CFBundleIdentifier"] as? String else { return nil }
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
            ?? bundle.deletingPathExtension().lastPathComponent
        var app = GuestApp(id: id, name: name, bundleURL: bundle, icon: icon(in: bundle, info: info), isBundled: bundled)
        app.size = size(of: bundle)
        return app
    }

    /// App icon: the largest PNG among the icons declared in Info.plist.
    private static func icon(in bundle: URL, info: NSDictionary) -> UIImage? {
        var names: [String] = []
        for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            if let icons = info[key] as? [String: Any],
               let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
               let files = primary["CFBundleIconFiles"] as? [String] {
                names += files
            }
        }
        if let files = info["CFBundleIconFiles"] as? [String] { names += files }
        guard !names.isEmpty,
              let all = try? FileManager.default.contentsOfDirectory(at: bundle, includingPropertiesForKeys: [.fileSizeKey])
        else { return nil }
        let best = all
            .filter { url in url.pathExtension.lowercased() == "png" && names.contains { url.lastPathComponent.hasPrefix($0) } }
            .max { a, b in
                let sa = (try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let sb = (try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return sa < sb
            }
        return best.flatMap { UIImage(contentsOfFile: $0.path) }
    }
}
