import Foundation
import Security

/// Holds the signing certificate the user imported (.p12 + password + .mobileprovision), stored in iDesk's Keychain.
final class SigningStore: ObservableObject {
    static let shared = SigningStore()

    @Published private(set) var identity: CodeSigner.Identity?
    @Published private(set) var profile: ProvisioningProfile?

    private let service = "iDesk.signing"

    private init() {
        migrateKeychainProtection()
        if let p12 = read("p12"), let password = read("password").map({ String(decoding: $0, as: UTF8.self) }) {
            identity = try? CodeSigner.loadIdentity(p12: p12, password: password)
        }
        profile = read("profile").flatMap(ProvisioningProfile.init(data:))
    }

    /// Whether the profile accepts the current certificate. nil = one of them is missing.
    var profileMatchesCertificate: Bool? {
        guard let identity, let profile else { return nil }
        return profile.contains(identity)
    }

    func importProfile(_ data: Data) throws {
        guard let parsed = ProvisioningProfile(data: data) else {
            throw CodeSigner.Failure.badCertificate(String(localized: "the .mobileprovision file is damaged or in the wrong format."))
        }
        write("profile", data)
        profile = parsed
    }

    /// iDesk's own Team ID (from its current signature). Guest apps must be signed with the same Team ID.
    var ownTeamID: String? { OwnSignature.teamID }

    /// Whether the imported certificate has the same Team ID as iDesk. nil = unknown.
    var matchesOwnTeam: Bool? {
        guard let identity, let own = ownTeamID, !own.isEmpty else { return nil }
        return identity.teamID == own
    }

    func importCertificate(p12: Data, password: String) throws {
        let loaded = try CodeSigner.loadIdentity(p12: p12, password: password)
        write("p12", p12)
        write("password", Data(password.utf8))
        identity = loaded
    }

    func removeCertificate() {
        for account in ["p12", "password", "profile"] {
            SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                           kSecAttrAccount: account] as CFDictionary)
        }
        identity = nil
        profile = nil
    }

    private func read(_ account: String) -> Data? {
        var out: CFTypeRef?
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
                     kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary
        return SecItemCopyMatching(query, &out) == errSecSuccess ? out as? Data : nil
    }

    private func write(_ account: String, _ data: Data) {
        let key = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary
        // A signing identity is only needed while the user is actively signing an export.
        // ThisDeviceOnly also keeps it out of iCloud Keychain / migrated backups.
        let attributes: [CFString: Any] = [kSecValueData: data,
                                           kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        // Update first: delete-then-add could silently lose the certificate if Add fails.
        let status = SecItemUpdate(key, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
                                         kSecAttrService: service,
                                         kSecAttrAccount: account]
            item.merge(attributes) { _, new in new }
            let added = SecItemAdd(item as CFDictionary, nil)
            if added != errSecSuccess {
                APLog.error("Keychain add failed for \(account) (code \(added))", module: "Signing")
            }
        } else if status != errSecSuccess {
            APLog.error("Keychain update failed for \(account) (code \(status))", module: "Signing")
        }
    }

    /// Migration for items written by older builds with AfterFirstUnlock. Guarded by a flag so a
    /// failed migration is retried next launch, but a successful one never rewrites the identity.
    private func migrateKeychainProtection() {
        let migratedKey = "APLite.signing.protectionMigrated.v1"
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return }
        for account in ["p12", "password", "profile"] {
            // write() updates the accessibility class in place; it never deletes a working item.
            if let data = read(account) { write(account, data) }
        }
        UserDefaults.standard.set(true, forKey: migratedKey)
    }
}
