import Foundation

/// Provisioning profile (.mobileprovision) that comes with a purchased certificate.
struct ProvisioningProfile {
    let data: Data
    let name: String
    let expiration: Date?
    let certificates: [Data]        // DER of the certificates this profile accepts

    var isExpired: Bool { expiration.map { $0 < Date() } ?? false }

    /// A .mobileprovision file is a plist wrapped in a CMS signature: just cut out the plist.
    init?(data: Data) {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                from: Data(data[start.lowerBound..<end.upperBound]), format: nil) as? [String: Any]
        else { return nil }
        self.data = data
        name = plist["Name"] as? String ?? "?"
        expiration = plist["ExpirationDate"] as? Date
        certificates = plist["DeveloperCertificates"] as? [Data] ?? []
    }

    func contains(_ identity: CodeSigner.Identity) -> Bool { certificates.contains(identity.leaf) }
}

/// Files the user picks when importing a certificate: .p12, .mobileprovision, pass.txt,
/// or an ESign-style .zip with all three. A mistakenly picked IPA is recognized too.
struct CertificateFiles {
    var p12: Data?
    var profile: Data?
    var passwordTexts: [String] = []
    var ipas: [URL] = []
    var unknown: [String] = []
    /// Why a .p12 / .pfx could not be read from Files (never a password or key).
    var readErrors: [String] = []

    var isEmpty: Bool { p12 == nil && profile == nil && ipas.isEmpty }

    static func collect(_ urls: [URL]) -> CertificateFiles {
        var files = CertificateFiles()
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            files.absorb(url, allowZip: true)
        }
        return files
    }

    private mutating func absorb(_ url: URL, allowZip: Bool) {
        switch url.pathExtension.lowercased() {
        case "ipa":
            ipas.append(url)
        case "zip" where allowZip:
            let names = (try? Unzip.entryNames(url)) ?? []
            if names.contains(where: { $0.hasPrefix("Payload/") }) {
                ipas.append(url)
                return
            }
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("cert-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: work) }
            guard (try? Unzip.extract(url, to: work)) != nil else {
                unknown.append(url.lastPathComponent)
                return
            }
            let inside = FileManager.default.enumerator(at: work, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL } ?? []
            for file in inside where !file.hasDirectoryPath { absorb(file, allowZip: false) }
        case "p12", "pfx":
            do {
                let data = try Data(contentsOf: url)
                if data.isEmpty { readErrors.append("\(url.lastPathComponent): \(String(localized: "the file is empty."))") }
                else { p12 = data }
            } catch {
                readErrors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        case "mobileprovision", "provisionprofile":
            profile = try? Data(contentsOf: url)
        case "txt":
            if let text = try? String(contentsOf: url, encoding: .utf8) { passwordTexts.append(text) }
        default:
            unknown.append(url.lastPathComponent)
        }
    }

    /// Opens the .p12: tries the typed password, then passwords read from pass.txt, then an empty one.
    func unlock(typed: String? = nil) throws -> (identity: CodeSigner.Identity, password: String) {
        guard let p12 else {
            if let reason = readErrors.first { throw CodeSigner.Failure.badCertificate(reason) }
            throw CodeSigner.Failure.badCertificate(String(localized: "no .p12 or .pfx file chosen."))
        }
        var candidates: [String] = []
        for raw in (typed.map { [$0] } ?? []) + passwordTexts {
            candidates += [Self.cleanPassword(raw), raw.trimmingCharacters(in: .whitespacesAndNewlines)]
            // pass.txt may have several lines: try each.
            candidates += raw.split(whereSeparator: \.isNewline).map { Self.cleanPassword(String($0)) }
        }
        if typed == nil { candidates.append("") }

        var seen = Set<String>()
        var lastError: Error = CodeSigner.Failure.badCertificate(String(localized: "wrong password."))
        for password in candidates where seen.insert(password).inserted {
            do { return (try CodeSigner.loadIdentity(p12: p12, password: password), password) }
            catch { lastError = error }
        }
        throw lastError
    }

    /// "Password: abc123" or "pass = abc123" → "abc123". Sellers often add a label in pass.txt.
    static func cleanPassword(_ raw: String) -> String { CertificateRules.cleanPassword(raw) }
}
