import Foundation
import Security
import CryptoKit
import LocalAuthentication

/// Typed security errors. Messages never include the passcode, its hash or keychain data.
enum SecurityFailure: LocalizedError {
    case tooShort
    case mismatch
    case noPasscode
    case wrongPasscode(attempts: Int)
    case lockedOut(TimeInterval)
    case keychain(OSStatus)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .tooShort: return String(localized: "Use at least 4 characters.")
        case .mismatch: return String(localized: "The new passcodes do not match.")
        case .noPasscode: return String(localized: "No APLite passcode is set. Choose one in Settings → Security.")
        case .wrongPasscode(let attempts):
            return attempts >= 3
                ? String(localized: "Incorrect passcode. \(attempts) failed attempts — further attempts will be delayed.")
                : String(localized: "Incorrect passcode.")
        case .lockedOut(let seconds):
            return String(localized: "Too many attempts. Try again in \(Int(seconds.rounded())) seconds.")
        case .keychain: return String(localized: "The Keychain could not be accessed. Check the device passcode and try again.")
        case .unavailable: return String(localized: "Authentication is not available on this device.")
        }
    }
}

/// Owns APLite's lock state, passcode and anti-brute-force policy.
///
/// The passcode is **never** stored: only a salted SHA-256 hash and its random salt, both in the
/// Keychain with `AfterFirstUnlock`. Failed attempts and the lockout deadline are not secrets and
/// live in UserDefaults, so a reinstall of the app keeps the throttle but not the hash.
final class SecurityManager: ObservableObject {
    static let shared = SecurityManager()

    @Published private(set) var isConfigured = false
    @Published private(set) var isLocked = false
    @Published private(set) var failedAttempts = 0
    @Published private(set) var lockoutUntil: Date?

    private let service = "com.hieuk.aplite.security"
    private let hashAccount = "passcode.hash.v1"
    private let saltAccount = "passcode.salt.v1"
    private let attemptsKey = "APLite.security.attempts"
    private let lockoutKey = "APLite.security.lockout"

    private init() {
        isConfigured = read(hashAccount) != nil && read(saltAccount) != nil
        failedAttempts = UserDefaults.standard.integer(forKey: attemptsKey)
        lockoutUntil = UserDefaults.standard.object(forKey: lockoutKey) as? Date
        // A deadline in the past is stale state, not a lockout.
        if let deadline = lockoutUntil, deadline <= Date() { clearThrottle() }
    }

    // MARK: Passcode management

    func setPasscode(_ passcode: String, confirm: String? = nil) throws {
        guard passcode.count >= 4 else { throw SecurityFailure.tooShort }
        if let confirm, passcode != confirm { throw SecurityFailure.mismatch }
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let hash = Self.digest(passcode, salt: salt)
        try write(hash, account: hashAccount)
        try write(salt, account: saltAccount)
        isConfigured = true
        APLiteSettings.Security.useOwnPasscode = true
        clearThrottle()
    }

    func changePasscode(current: String, to new: String, confirm: String? = nil) throws {
        guard isConfigured else { throw SecurityFailure.noPasscode }
        try verifyPasscode(current)
        try setPasscode(new, confirm: confirm)
    }

    func removePasscode() {
        delete(hashAccount); delete(saltAccount)
        isConfigured = false
        APLiteSettings.Security.useOwnPasscode = false
        clearThrottle()
    }

    /// Verifies a passcode and applies exponential backoff. Throws instead of ever revealing
    /// whether the hash or the salt was wrong.
    func verifyPasscode(_ candidate: String) throws {
        guard let deadline = lockoutUntil, deadline > Date() else {
            if lockoutUntil != nil { clearThrottle() }   // deadline passed
            guard let hash = read(hashAccount), let salt = read(saltAccount) else {
                throw SecurityFailure.noPasscode
            }
            guard Self.digest(candidate, salt: salt) == hash else {
                recordFailure()
                throw SecurityFailure.wrongPasscode(attempts: failedAttempts)
            }
            clearThrottle()
            return
        }
        throw SecurityFailure.lockedOut(deadline.timeIntervalSinceNow)
    }

    // MARK: Brute-force protection

    private func recordFailure() {
        failedAttempts += 1
        let delay: TimeInterval
        switch failedAttempts {
        case 1, 2: delay = 0
        case 3...4: delay = 30
        case 5...7: delay = 120
        case 8...9: delay = 600
        default: delay = 3600
        }
        if delay > 0 { lockoutUntil = Date().addingTimeInterval(delay) }
        persistThrottle()
    }

    private func clearThrottle() {
        failedAttempts = 0
        lockoutUntil = nil
        UserDefaults.standard.removeObject(forKey: attemptsKey)
        UserDefaults.standard.removeObject(forKey: lockoutKey)
    }

    private func persistThrottle() {
        UserDefaults.standard.set(failedAttempts, forKey: attemptsKey)
        if let deadline = lockoutUntil { UserDefaults.standard.set(deadline, forKey: lockoutKey) }
        else { UserDefaults.standard.removeObject(forKey: lockoutKey) }
    }

    /// Pure policy helper (unit tested): the delay in seconds for a given number of failures.
    static func backoffSeconds(for failures: Int) -> TimeInterval {
        switch failures {
        case 0..<3: return 0
        case 3...4: return 30
        case 5...7: return 120
        case 8...9: return 600
        default: return 3600
        }
    }

    // MARK: Device authentication

    /// Uses Face ID / Touch ID with the iOS passcode as fallback. APLite's own passcode is checked
    /// separately by the UI when configured; both paths end in `unlock()`.
    func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel")
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(false)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func unlock() { isLocked = false }
    func lock() { isLocked = true }

    // MARK: Keychain (no secret ever logged)

    private static func digest(_ passcode: String, salt: Data) -> Data {
        var input = salt
        input.append(contentsOf: passcode.utf8)
        return Data(SHA256.hash(data: input))
    }

    private func read(_ account: String) -> Data? {
        var item: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess ? item as? Data : nil
    }

    private func write(_ data: Data, account: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecurityFailure.keychain(status) }
    }

    private func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
