import Foundation

/// Pure rules for certificate import, kept free of Keychain/UIKit so they can be unit tested.
enum CertificateRules {
    static let extensions = ["p12", "pfx"]

    static func isSupported(_ pathExtension: String) -> Bool {
        extensions.contains(pathExtension.lowercased())
    }

    /// Sellers often put "Password: abc" in pass.txt. Return the value, never log it.
    static func cleanPassword(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sep = s.firstIndex(where: { $0 == ":" || $0 == "=" }) else { return s }
        let label = s[..<sep].trimmingCharacters(in: .whitespaces).lowercased()
        let labels = ["password", "pass", "passwd", "pwd", "mật khẩu", "mat khau", "mk", "p12 password", "cert password"]
        guard labels.contains(label) else { return s }
        return s[s.index(after: sep)...].trimmingCharacters(in: .whitespaces)
    }
}
