import Foundation
import CryptoKit

/// Pure catalogue/integrity helpers for the internal APStore. No IPA-from-outside promises:
/// iOS code signing and the sandbox make arbitrary IPA installation impossible for a third-party app.
enum APStoreCatalog {
    enum Kind: String, Codable, Equatable {
        case webApp
        case nativeModule
    }

    struct Listing: Identifiable, Equatable {
        let id: String
        let title: String
        let kind: Kind
        let detail: String
        let installed: Bool
    }

    static func webListings(installed: (String) -> Bool) -> [Listing] {
        BuiltInWebApp.allCases.map { app in
            Listing(id: "web.\(app.title)", title: app.title, kind: .webApp,
                    detail: app.url, installed: installed(app.url))
        }
    }

    static func nativeListings(from apps: [GuestApp]) -> [Listing] {
        apps.map { app in
            Listing(id: "native.\(app.id)", title: app.name, kind: .nativeModule,
                    detail: app.status.text, installed: app.isBundled)
        }
    }
}

/// Hash check for APLite-owned packages before they are trusted. The expected digest comes from
/// APLite's own manifest, never from the untrusted file itself.
enum APStoreIntegrity {
    static func sha256Hex(of data: Data) -> String {
        Data(SHA256.hash(data: data)).map { String(format: "%02x", Int($0)) }.joined()
    }

    static func sha256Hex(ofFile url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return sha256Hex(of: data)
    }

    static func matches(data: Data, expectedHex: String) -> Bool {
        sha256Hex(of: data).caseInsensitiveCompare(expectedHex) == .orderedSame
    }
}
