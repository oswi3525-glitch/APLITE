import Foundation
import Security

/// Pure mapping of `SecPKCS12Import` statuses to an honest explanation.
///
/// iOS returns `errSecAuthFailed` for a wrong password **and** for a corrupted/truncated file, and
/// `errSecParam` / `errSecDecode` for a valid PKCS#12 that uses modern (OpenSSL 3) encryption which
/// `SecPKCS12Import` cannot read. Collapsing all of those into "damaged" or "wrong password" sent
/// users in circles — re-picking the original file never helped.
enum P12ImportErrorMapper {
    enum Reason: Equatable {
        case wrongPasswordOrDamaged
        case unsupportedEncryptionOrDamaged
        case other(Int)
    }

    static func reason(for status: OSStatus) -> Reason {
        switch status {
        case errSecAuthFailed: return .wrongPasswordOrDamaged
        case errSecParam, errSecDecode: return .unsupportedEncryptionOrDamaged
        default: return .other(Int(status))
        }
    }

    static func message(for reason: Reason) -> String {
        switch reason {
        case .wrongPasswordOrDamaged:
            return String(localized: "The password is wrong, or the file is damaged. Check the password and choose the original .p12 / .pfx again.")
        case .unsupportedEncryptionOrDamaged:
            return String(localized: "iOS cannot read this PKCS#12 file. It may use modern encryption: re-export it with `openssl pkcs12 -export -legacy ...` and try again.")
        case .other(let code):
            return String(localized: "iOS could not import the certificate (code \(code)). Re-export the .p12 with legacy encryption and try again.")
        }
    }
}
