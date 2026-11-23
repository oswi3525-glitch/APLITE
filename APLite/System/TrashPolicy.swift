import Foundation

/// Pure decision layer for dropping an icon on the Trash. iOS gives one app no API to uninstall
/// another app, so the only honest outcomes are: delete APLite-owned data, mark a bundled guest app
/// for the next re-sign/reinstall, or explain why an item cannot be removed. Foundation-only for tests.
enum TrashPolicy {
    enum Outcome: Equatable {
        case unsupportedSystemItem
        case moveFileToTrash
        case uninstallWebApp
        case uninstallGuestApp
        case markGuestForReinstall
        case removeShortcut
    }

    static func outcome(systemPage: Bool, trash: Bool, file: Bool, webApp: Bool,
                        guestApp: Bool, guestRemovable: Bool) -> Outcome {
        if systemPage || trash { return .unsupportedSystemItem }
        if file { return .moveFileToTrash }
        if webApp { return .uninstallWebApp }
        if guestApp { return guestRemovable ? .uninstallGuestApp : .markGuestForReinstall }
        return .removeShortcut
    }
}
