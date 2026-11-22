import Foundation

/// Turns common `dlopen` / dyld errors when loading a guest app into plain explanations,
/// with the raw error appended so the user can send it.
enum LaunchDiagnostics {
    static func explain(_ raw: String) -> String {
        let s = raw.lowercased()
        let hint: String
        if s.contains("sandbox blocked mmap") || s.contains("sandbox blocked") {
            hint = String(localized: "iOS only runs code inside an installed app, not from iDesk’s data folder.") + " " + installTip
        } else if s.contains("different team id") || s.contains("team ids") {
            hint = String(localized: "The guest app and iDesk are signed with different Team IDs.") + " " + installTip
        } else if s.contains("no team id") || s.contains("not signed") || s.contains("unsigned") || s.contains("adhoc") || s.contains("ad-hoc") {
            hint = String(localized: "The guest app is not signed.") + " " + installTip
        } else if s.contains("library not loaded") || s.contains("image not found") {
            hint = String(localized: "The app needs a library (framework) iDesk cannot find or sign. The IPA may lack its Frameworks folder, or use a system library this iOS version does not have.")
        } else if s.contains("incompatible") || s.contains("architecture") || s.contains("arm64e") {
            hint = String(localized: "The app’s executable has no arm64 version suitable for this iPhone.")
        } else if s.contains("symbol not found") && (s.contains("substrate") || s.contains("ellekit") || s.contains("tweak")) {
            hint = String(localized: "This IPA has a tweak injected, with an old hook library that calls functions this iOS removed. Delete the app in iDesk and add the IPA again: newer iDesk versions patch this when adding. If it still fails or quits on launch, use an IPA without tweaks.")
        } else if s.contains("symbol not found") {
            hint = String(localized: "The app needs a newer iOS version, or uses a system function this device does not have.")
        } else if s.contains("code signature") || s.contains("signature") || s.contains("codesign")
                    || s.contains("not valid for use") || s.contains("system policy") || s.contains("untrusted") {
            hint = String(localized: "iOS rejected the guest app’s signature.") + " " + installTip
        } else if s.contains("fairplay") || s.contains("encrypt") {
            hint = String(localized: "The app is still encrypted (an IPA straight from the App Store). iDesk can only load decrypted IPAs.")
        } else {
            hint = String(localized: "Unknown cause. Tap “Copy error” and send the full text so it can be looked into.")
        }
        return hint + "\n\n" + String(localized: "Details:") + " " + raw
    }

    /// How to make it work with a normal certificate: install the app into iDesk through a signing app.
    static var installTip: String {
        String(localized: "Tap the box button → “Install new apps into iDesk”, pick ESign (or your signing app), then sign and install as usual.")
    }
}
