import Foundation
import Security

/// A build record as reported by GitHub. `conclusion` is the runner's real result — this module
/// never invents one.
struct BuildRecord: Identifiable, Equatable {
    let id: Int
    let status: String
    let conclusion: String?
    let createdAt: String
    let htmlURL: URL?

    var display: String {
        "\(status)\(conclusion.map { " · \($0)" } ?? "")"
    }
}

enum BuildCenterError: LocalizedError {
    case notConfigured
    case badResponse
    case http(Int)
    case noIPA

    var errorDescription: String? {
        switch self {
        case .notConfigured: return String(localized: "Add a GitHub repository and token in Build Center first.")
        case .badResponse: return String(localized: "The build worker returned an unexpected response.")
        case .http(let code): return String(localized: "The build worker returned HTTP \(code).")
        case .noIPA: return String(localized: "This run has no IPA artifact yet. A failed or running build has no download.")
        }
    }
}

/// Talks to a real GitHub Actions macOS worker. APLite cannot build iOS apps on iOS: Xcode is not
/// available, so this module analyses the project locally and delegates compilation to Actions.
final class BuildCenter: ObservableObject {
    static let shared = BuildCenter()

    @Published private(set) var analysis: ProjectAnalysis?
    @Published private(set) var builds: [BuildRecord] = []
    @Published private(set) var status = String(localized: "No build requested")
    @Published private(set) var lastError: String?

    private let service = "com.hieuk.aplite.buildcenter"
    private let ownerKey = "APLite.build.owner"
    private let repoKey = "APLite.build.repo"
    private let defaults = UserDefaults.standard

    var owner: String { defaults.string(forKey: ownerKey) ?? "" }
    var repo: String { defaults.string(forKey: repoKey) ?? "" }
    var isConfigured: Bool { !owner.isEmpty && !repo.isEmpty && (try? readToken()) != nil }

    // MARK: Configuration

    func configure(owner: String, repo: String, token: String) throws {
        guard !owner.isEmpty, !repo.isEmpty, !token.isEmpty else { throw BuildCenterError.notConfigured }
        defaults.set(owner, forKey: ownerKey)
        defaults.set(repo, forKey: repoKey)
        try writeToken(token)
        lastError = nil
    }

    // MARK: Local analysis

    /// Reads the files picked from Files inside their security scope and analyses what is there.
    func analyze(_ urls: [URL]) throws -> ProjectAnalysis {
        var files: [(name: String, text: String)] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let text = String(decoding: data.prefix(2_000_000), as: UTF8.self)
            files.append((url.lastPathComponent, text))
        }
        guard !files.isEmpty else { throw BuildCenterError.badResponse }
        let result = ProjectAnalyzer.analyze(files: files)
        analysis = result
        return result
    }

    // MARK: Worker

    func requestBuild(workflow: String = "build.yml", ref: String = "main") async throws {
        guard isConfigured else { throw BuildCenterError.notConfigured }
        let path = "/repos/\(owner)/\(repo)/actions/workflows/\(workflow)/dispatches"
        var request = makeRequest(path, method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["ref": ref])
        let (_, response) = try await URLSession.shared.data(for: request)
        try check(response)
        // 204 means the request was accepted, NOT that a build succeeded.
        status = String(localized: "Build requested for \(ref) — waiting for the macOS runner")
        lastError = nil
    }

    func refreshBuilds() async throws {
        guard isConfigured else { throw BuildCenterError.notConfigured }
        let (data, response) = try await URLSession.shared.data(for: makeRequest("/repos/\(owner)/\(repo)/actions/runs?per_page=10"))
        try check(response)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runs = json["workflow_runs"] as? [[String: Any]] else { throw BuildCenterError.badResponse }
        builds = runs.compactMap { run in
            guard let id = run["id"] as? Int, let state = run["status"] as? String else { return nil }
            return BuildRecord(id: id, status: state, conclusion: run["conclusion"] as? String,
                               createdAt: run["created_at"] as? String ?? "",
                               htmlURL: (run["html_url"] as? String).flatMap(URL.init(string:)))
        }
        if let first = builds.first { status = first.display }
    }

    /// Downloads the IPA of a *successful* run. Never fabricates an artifact.
    func downloadIPA(for build: BuildRecord) async throws -> URL {
        guard isConfigured else { throw BuildCenterError.notConfigured }
        guard build.conclusion == "success" else { throw BuildCenterError.noIPA }
        let (data, response) = try await URLSession.shared.data(
            for: makeRequest("/repos/\(owner)/\(repo)/actions/runs/\(build.id)/artifacts"))
        try check(response)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let artifacts = json["artifacts"] as? [[String: Any]],
              let ipa = artifacts.first(where: { (($0["name"] as? String) ?? "").lowercased().contains("ipa") }),
              let urlString = ipa["archive_download_url"] as? String,
              let url = URL(string: urlString) else { throw BuildCenterError.noIPA }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try readToken())", forHTTPHeaderField: "Authorization")
        let (archive, downloadResponse) = try await URLSession.shared.data(for: request)
        try check(downloadResponse)
        let target = APLiteFileManager.systemRoot
            .appendingPathComponent("APLite-\(build.id).zip")
        try archive.write(to: target)
        return target
    }

    // MARK: Internals

    private func makeRequest(_ path: String, method: String = "GET") -> URLRequest {
        let url = URL(string: "https://api.github.com" + path)!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \( (try? readToken()) ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("APLite", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw BuildCenterError.badResponse }
        guard (200...299).contains(http.statusCode) else { throw BuildCenterError.http(http.statusCode) }
    }

    private func readToken() throws -> String {
        var item: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "token",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { throw BuildCenterError.notConfigured }
        return String(decoding: data, as: UTF8.self)
    }

    private func writeToken(_ token: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "token",
        ]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw BuildCenterError.notConfigured }
    }
}
