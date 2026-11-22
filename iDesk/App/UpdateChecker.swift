import SwiftUI

/// Looks for a newer iDesk on GitHub Releases (itshieuk/iDesk): at launch and on return, at most hourly, unless off in
/// Settings → Help, and from "Check for updates" there. Nothing is sent but the request itself.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct Release: Equatable {
        let version: String
        let page: URL
        let ipa: URL?
    }

    @Published private(set) var available: Release?
    @Published private(set) var checking = false
    @Published private(set) var lastResult: String?
    /// The iPhone's banner was closed for this version.
    @Published var dismissedVersion: String? = UserDefaults.standard.string(forKey: dismissedKey) {
        didSet { UserDefaults.standard.set(dismissedVersion, forKey: Self.dismissedKey) }
    }

    private static let api = URL(string: "https://api.github.com/repos/itshieuk/iDesk/releases/latest")!
    private static let autoKey = "iDesk.checkUpdates", lastKey = "iDesk.lastUpdateCheck", dismissedKey = "iDesk.updateDismissed"

    static var current: String {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-iDeskFakeVersion"), i + 1 < args.count { return args[i + 1] }   // to test the banner
        #endif
        return Bundle.iDesk.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var automatic: Bool {
        get { UserDefaults.standard.object(forKey: Self.autoKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.autoKey); objectWillChange.send() }
    }

    /// At launch and whenever iDesk comes back to the front: at most once an hour (a release published since the last
    /// look is seen the next time iDesk opens, not a day later).
    func checkIfDue() {
        guard automatic else { return }
        let last = UserDefaults.standard.double(forKey: Self.lastKey)
        if Date().timeIntervalSince1970 - last > 3600 { check(userAsked: false) }
    }

    private var foregroundObserver: NSObjectProtocol?

    /// Called once at launch: checks now and each time iDesk returns to the front.
    func startChecking() {
        checkIfDue()
        guard foregroundObserver == nil else { return }
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in self?.checkIfDue() }
    }

    func check(userAsked: Bool) {
        guard !checking else { return }
        checking = true
        var request = URLRequest(url: Self.api, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("iDesk", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            if let json, let tag = json["tag_name"] as? String,
               let page = (json["html_url"] as? String).flatMap(URL.init(string:)) {
                let ipa = (json["assets"] as? [[String: Any]])?
                    .first { ($0["name"] as? String)?.lowercased().hasSuffix(".ipa") == true }
                    .flatMap { $0["browser_download_url"] as? String }.flatMap(URL.init(string:))
                DispatchQueue.main.async { self.found(tag: tag, page: page, ipa: ipa, userAsked: userAsked) }
            } else {
                // The API refused (60 requests an hour per address, often shared by a whole mobile network) or
                // failed: github.com's own /releases/latest redirects to the newest tag and has no such limit.
                self.checkByRedirect(userAsked: userAsked)
            }
        }.resume()
    }

    /// github.com/<repo>/releases/latest → …/releases/tag/vX.Y.Z; the IPA's name follows the release workflow.
    private func checkByRedirect(userAsked: Bool) {
        var request = URLRequest(url: URL(string: "https://github.com/itshieuk/iDesk/releases/latest")!, timeoutInterval: 15)
        request.httpMethod = "HEAD"
        request.setValue("iDesk", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let final = (response as? HTTPURLResponse)?.url
            DispatchQueue.main.async {
                guard let final, final.path.contains("/releases/tag/") else {
                    self.checking = false
                    self.lastResult = String(localized: "Could not reach GitHub. Try again later.")
                    if userAsked { DesktopModel.shared.showToast(self.lastResult ?? "") }
                    return
                }
                let tag = final.lastPathComponent
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let ipa = URL(string: "https://github.com/itshieuk/iDesk/releases/download/\(tag)/iDesk-\(version).ipa")
                self.found(tag: tag, page: final, ipa: ipa, userAsked: userAsked)
            }
        }.resume()
    }

    private func found(tag: String, page: URL, ipa: URL?, userAsked: Bool) {
        checking = false
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastKey)
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        if Self.isNewer(version, than: Self.current) {
            let isNew = available?.version != version
            available = Release(version: version, page: page, ipa: ipa)
            lastResult = String(localized: "iDesk \(version) is available.")
            if isNew || userAsked {
                DesktopModel.shared.showToast(String(localized: "iDesk \(version) is available: Settings → Help to download it."))
            }
        } else {
            available = nil
            lastResult = String(localized: "iDesk \(Self.current) is the latest version.")
            if userAsked { DesktopModel.shared.showToast(lastResult ?? "") }
        }
    }

    /// "0.6.10" is newer than "0.6.9".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// What the update is doing: downloading (0…1), then packaging with the apps (0…1).
    enum Step: Equatable { case downloading(Double), packaging(Double) }
    @Published private(set) var step: Step?
    private var progressObservation: NSKeyValueObservation?

    /// Downloads the new iDesk, puts the iOS apps of this iDesk into it, and hands the one IPA to the signing app
    /// (ESign…): signing and installing it updates iDesk and keeps the apps. Without apps, the new IPA goes as it is.
    func download() {
        guard let release = available, step == nil else { return }
        guard let ipa = release.ipa else { UIApplication.shared.open(release.page); return }
        let model = DesktopModel.shared
        step = .downloading(0)
        model.showToast(String(localized: "Downloading iDesk \(release.version)…"))
        let task = URLSession.shared.downloadTask(with: ipa) { [weak self] temp, _, error in
            guard let self else { return }
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("update-\(UUID().uuidString)", isDirectory: true)
            let file = work.appendingPathComponent("iDesk-\(release.version).ipa")
            var failure: String? = error?.localizedDescription
            if failure == nil, let temp {
                do {
                    try fm.createDirectory(at: work, withIntermediateDirectories: true)
                    try fm.moveItem(at: temp, to: file)
                } catch { failure = error.localizedDescription }
            } else if failure == nil { failure = String(localized: "The download did not finish.") }
            DispatchQueue.main.async {
                self.progressObservation = nil
                if let failure {
                    self.step = nil
                    model.showToast(String(localized: "Could not download the update: \(failure)"))
                    return
                }
                self.package(file, version: release.version, work: work)
            }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            DispatchQueue.main.async { if case .downloading = self?.step { self?.step = .downloading(p.fractionCompleted) } }
        }
        task.resume()
    }

    private func package(_ ipa: URL, version: String, work: URL) {
        let model = DesktopModel.shared
        let hasApps = !GuestStore.shared.apps.isEmpty
        guard hasApps else {
            step = nil
            ShareSheet.present(ipa)
            model.showToast(String(localized: "Pick ESign (or your signing app) on the iPhone to install iDesk \(version)."))
            return
        }
        step = .packaging(0)
        DispatchQueue.global(qos: .userInitiated).async {
            let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
            let app: URL? = (try? Unzip.extract(ipa, to: unpacked)).flatMap { _ in
                (try? FileManager.default.contentsOfDirectory(at: unpacked.appendingPathComponent("Payload"), includingPropertiesForKeys: nil))?
                    .first { $0.pathExtension == "app" }
            }
            DispatchQueue.main.async {
                guard let app else {
                    self.step = nil
                    model.showToast(String(localized: "The downloaded file is not an iDesk IPA."))
                    return
                }
                GuestStore.shared.exportForESign(base: app, progress: { v in
                    DispatchQueue.main.async { self.step = .packaging(v) }
                }, completion: { result in
                    self.step = nil
                    // The packaged IPA is in Documents/Export: the download and its unpacked copy are done with.
                    try? FileManager.default.removeItem(at: work)
                    switch result {
                    case .success(let file):
                        ShareSheet.present(file)
                        model.showToast(String(localized: "iDesk \(version) with your apps is ready: pick ESign (or your signing app) on the iPhone."))
                    case .failure(let error):
                        model.showToast(String(localized: "Could not package the update: \(error.localizedDescription)"))
                    }
                })
            }
        }
    }

    /// For the banner and Settings: what the update is doing now.
    var stepText: String? {
        switch step {
        case .downloading(let f)?: return String(localized: "Downloading… \(Int(f * 100))%")
        case .packaging(let f)?: return String(localized: "Adding your apps… \(Int(f * 100))%")
        case nil: return nil
        }
    }
}

/// On the iPhone: a new version is out.
struct UpdateBanner: View {
    @ObservedObject var updates = UpdateChecker.shared
    var body: some View {
        if let r = updates.available, updates.dismissedVersion != r.version {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill").font(.title3).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: String(localized: "iDesk \(r.version) is available")).font(.callout.weight(.semibold))
                    Text(verbatim: updates.stepText ?? String(localized: "You have \(UpdateChecker.current). Your iOS apps stay: they are put into the new version."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Update") { updates.download() }.buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(updates.step != nil)
                Button { updates.dismissedVersion = r.version } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 14)
        }
    }
}
