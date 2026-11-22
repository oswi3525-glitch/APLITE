import Foundation

/// APLite's certificate façade. It recognizes .p12 / .pfx, reads security-scoped files from Files,
/// checks the password and reports a specific error for each failure. Passwords, private keys and
/// raw PKCS#12 bytes are never logged or included in an error message.
final class CertificateManager: ObservableObject {
    static let shared = CertificateManager()

    @Published private(set) var status = String(localized: "No certificate imported")
    @Published private(set) var lastError: String?

    private let store = SigningStore.shared

    var supportedExtensions: [String] { CertificateRules.extensions }
    var identityName: String? { store.identity?.commonName }
    var teamID: String? { store.identity?.teamID }
    var hasIdentity: Bool { store.identity != nil }
    var profileMatches: Bool? { store.profileMatchesCertificate }

    /// Reads a picked file while its security scope is open. A failed read is a specific error.
    func readCertificate(from url: URL) throws -> Data {
        guard CertificateRules.isSupported(url.pathExtension) else { throw CodeSigner.Failure.p12UnsupportedFormat }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { throw CodeSigner.Failure.p12Damaged }
            return data
        } catch let error as CodeSigner.Failure {
            throw error
        } catch {
            throw CodeSigner.Failure.badCertificate(String(localized: "The file could not be read from Files: \(error.localizedDescription)"))
        }
    }

    /// Verifies a password without storing anything. Returns the parsed identity on success.
    func verify(p12 data: Data, password: String) throws -> CodeSigner.Identity {
        try CodeSigner.loadIdentity(p12: data, password: password)
    }

    /// Imports into the existing Keychain-backed SigningStore so the Guest Engine keeps working.
    func `import`(p12 data: Data, password: String) throws {
        do {
            try store.importCertificate(p12: data, password: password)
            lastError = nil
            status = String(localized: "Certificate imported: \(store.identity?.commonName ?? String(localized: "unknown"))")
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func importProfile(_ data: Data) throws {
        do {
            try store.importProfile(data)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func remove() {
        store.removeCertificate()
        status = String(localized: "No certificate imported")
        lastError = nil
    }
}
