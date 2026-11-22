import Foundation
import CryptoKit
import Security

/// Re-signs Mach-O files on the device, without external tools.
///
/// Why: iOS only loads validly signed code, and extra libraries must share the main app's Team ID.
/// A patched guest app (MachOPatcher) loses its signature, so iDesk re-signs it with the same certificate
/// that signed iDesk (the .p12 from ESign / SideStore / a developer account).
/// The Simulator only needs an ad-hoc signature (no certificate).
enum CodeSigner {
    enum Failure: LocalizedError {
        case notThinMachO
        case noSignatureSlot
        case badCertificate(String)
        case signingFailed(String)

        var errorDescription: String? {
            switch self {
            case .notThinMachO: return String(localized: "The file is not a single-architecture 64-bit Mach-O.")
            case .noSignatureSlot: return String(localized: "The file was never signed, so it has no room for a signature.")
            case .badCertificate(let s): return String(localized: "Unusable certificate: \(s)")
            case .signingFailed(let s): return String(localized: "Signing failed: \(s)")
            }
        }
    }

    /// Certificate + private key used for signing.
    struct Identity {
        let key: SecKey
        let leaf: Data              // DER of the signing certificate
        let chain: [Data]           // intermediate + root certificates (DER)
        let teamID: String
        let commonName: String
    }

    // MARK: Signing one file

    /// Re-signs the file in place. `identity == nil` → ad-hoc signature.
    static func sign(_ url: URL, identifier: String, identity: Identity?) throws {
        var data = try Data(contentsOf: url)
        guard data.le32(0) == 0xfeed_facf else { throw Failure.notThinMachO }

        // Find LC_CODE_SIGNATURE, __LINKEDIT and __TEXT.
        var sigCommand = -1, linkedit = -1
        var textOffset: UInt64 = 0, textSize: UInt64 = 0
        var p = 32
        for _ in 0..<Int(data.le32(16)) {
            let cmd = data.le32(p), size = Int(data.le32(p + 4))
            guard size >= 8, p + size <= data.count else { throw Failure.notThinMachO }
            if cmd == 0x1d { sigCommand = p }
            if cmd == 0x19 {
                let name = data.cString(p + 8, max: 16)
                if name == "__LINKEDIT" { linkedit = p }
                if name == "__TEXT" { textOffset = data.le64(p + 40); textSize = data.le64(p + 48) }
            }
            p += size
        }
        guard sigCommand >= 0, linkedit >= 0 else { throw Failure.noSignatureSlot }

        let codeLimit = Int(data.le32(sigCommand + 8))
        guard codeLimit > 0, codeLimit <= data.count else { throw Failure.notThinMachO }
        data = Data(data.prefix(codeLimit))   // drop the old signature (always at the end of the file)

        // The signature size must be known up front: it goes into the header, which is itself hashed.
        let teamID = identity?.teamID ?? ""
        let slots = (codeLimit + 4095) / 4096
        let directorySize = 88 + identifier.utf8.count + 1 + (teamID.isEmpty ? 0 : teamID.utf8.count + 1) + (2 + slots) * 32
        let requirements = Data([0xfa, 0xde, 0x0c, 0x01, 0, 0, 0, 12, 0, 0, 0, 0])   // empty requirement set
        let cmsReserve = identity.map { 4096 + $0.leaf.count + $0.chain.reduce(0) { $0 + $1.count } } ?? 0
        let total = (12 + 3 * 8 + directorySize + requirements.count + 8 + cmsReserve + 15) & ~15

        data.setLE32(sigCommand + 12, UInt32(total))
        let linkeditOffset = Int(data.le64(linkedit + 40))
        let linkeditSize = UInt64(codeLimit + total - linkeditOffset)
        data.setLE64(linkedit + 48, linkeditSize)                               // filesize
        data.setLE64(linkedit + 32, (linkeditSize + 0x3fff) & ~0x3fff)          // vmsize, rounded to 16K pages

        // CodeDirectory
        var cd = Data()
        cd.appendBE32(0xfade_0c02)
        cd.appendBE32(UInt32(directorySize))
        cd.appendBE32(0x20400)                                    // version
        cd.appendBE32(identity == nil ? 0x2 : 0)                  // flags: adhoc
        let identOffset = 88
        let teamOffset = teamID.isEmpty ? 0 : identOffset + identifier.utf8.count + 1
        let hashOffset = directorySize - slots * 32
        cd.appendBE32(UInt32(hashOffset))
        cd.appendBE32(UInt32(identOffset))
        cd.appendBE32(2)                                          // nSpecialSlots
        cd.appendBE32(UInt32(slots))
        cd.appendBE32(UInt32(codeLimit))
        cd.append(contentsOf: [32, 2, 0, 12])               // hashSize, SHA-256, platform, 4K pages
        cd.appendBE32(0)                                          // spare2
        cd.appendBE32(0)                                          // scatterOffset
        cd.appendBE32(UInt32(teamOffset))
        cd.appendBE32(0)                                          // spare3
        cd.appendBE64(0)                                          // codeLimit64
        cd.appendBE64(textOffset)                                 // execSegBase
        cd.appendBE64(textSize)                                   // execSegLimit
        cd.appendBE64(0)                                          // execSegFlags
        cd.append(contentsOf: Array(identifier.utf8) + [0])
        if !teamID.isEmpty { cd.append(contentsOf: Array(teamID.utf8) + [0]) }
        cd.append(Data(SHA256.hash(data: requirements)))    // special slot -2: requirements
        cd.append(Data(count: 32))                          // special slot -1: Info.plist (none)
        for i in 0..<slots {
            let start = i * 4096
            cd.append(Data(SHA256.hash(data: data[start..<min(start + 4096, codeLimit)])))
        }
        precondition(cd.count == directorySize)

        // CMS signature (empty for ad-hoc)
        var cms = Data()
        cms.appendBE32(0xfade_0b01)
        let cmsBody = try identity.map { try makeCMS(directory: cd, identity: $0) } ?? Data()
        guard cmsBody.count <= cmsReserve else { throw Failure.signingFailed(String(localized: "the signature is larger than expected")) }
        cms.appendBE32(UInt32(8 + cmsBody.count))
        cms.append(cmsBody)

        // SuperBlob
        var blob = Data()
        blob.appendBE32(0xfade_0cc0)
        blob.appendBE32(UInt32(12 + 3 * 8 + cd.count + requirements.count + cms.count))
        blob.appendBE32(3)
        var offset = 12 + 3 * 8
        for (type, part) in [(UInt32(0), cd), (2, requirements), (0x10000, cms)] {
            blob.appendBE32(type)
            blob.appendBE32(UInt32(offset))
            offset += part.count
        }
        blob.append(cd)
        blob.append(requirements)
        blob.append(cms)
        blob.append(Data(count: total - blob.count))

        data.append(blob)
        // Write to a new file (new inode) so the system does not reuse the old signature check.
        try data.write(to: url, options: .atomic)
    }

    /// Signs every Mach-O file in the guest bundle: libraries first, the main executable last.
    static func signBundle(_ bundle: URL, executable: String, bundleID: String, identity: Identity?) throws {
        let fm = FileManager.default
        var files: [URL] = []
        if let walker = fm.enumerator(at: bundle, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in walker {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                      url.lastPathComponent != executable || url.deletingLastPathComponent().path != bundle.path,
                      MachOPatcher.isMachO(url) else { continue }
                files.append(url)
            }
        }
        for url in files {
            try MachOPatcher.thin(at: url)
            try sign(url, identifier: url.lastPathComponent, identity: identity)
        }
        try sign(bundle.appendingPathComponent(executable), identifier: bundleID, identity: identity)
    }


    // MARK: CMS (PKCS#7 SignedData, detached content)

    private static func makeCMS(directory: Data, identity: Identity) throws -> Data {
        let digest = Data(SHA256.hash(data: directory))
        let sha256 = DER.sequence(DER.oid([2, 16, 840, 1, 101, 3, 4, 2, 1]) + DER.null)
        let (issuer, serial) = try DER.issuerAndSerial(of: identity.leaf)

        // Apple-specific attributes: the cdhash list (plist and ASN.1 forms).
        let plist = try PropertyListSerialization.data(fromPropertyList: ["cdhashes": [digest.prefix(20)]],
                                                       format: .xml, options: 0)
        let time = DateFormatter()
        time.dateFormat = "yyMMddHHmmss'Z'"
        time.timeZone = TimeZone(identifier: "UTC")
        time.locale = Locale(identifier: "en_US_POSIX")

        func attribute(_ oid: [UInt], _ value: Data) -> Data { DER.sequence(DER.oid(oid) + DER.set(value)) }
        let attributes = [
            attribute([1, 2, 840, 113549, 1, 9, 3], DER.oid([1, 2, 840, 113549, 1, 7, 1])),
            attribute([1, 2, 840, 113549, 1, 9, 5], DER.tlv(0x17, Data(time.string(from: Date()).utf8))),
            attribute([1, 2, 840, 113549, 1, 9, 4], DER.octets(digest)),
            attribute([1, 2, 840, 113635, 100, 9, 1], DER.octets(plist)),
            attribute([1, 2, 840, 113635, 100, 9, 2],
                      DER.sequence(DER.oid([2, 16, 840, 1, 101, 3, 4, 2, 1]) + DER.octets(digest))),
        ].reduce(Data(), +)

        // The signature covers the attributes encoded as a SET (0x31); inside the CMS they are tagged [0].
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(identity.key, .rsaSignatureMessagePKCS1v15SHA256,
                                                    DER.set(attributes) as CFData, &error) as Data? else {
            throw Failure.signingFailed(error?.takeRetainedValue().localizedDescription ?? String(localized: "unknown"))
        }

        let signer = DER.sequence(
            DER.integer(1)
            + DER.sequence(issuer + serial)
            + sha256
            + DER.tlv(0xa0, attributes)
            + DER.sequence(DER.oid([1, 2, 840, 113549, 1, 1, 1]) + DER.null)
            + DER.octets(signature))

        let signedData = DER.sequence(
            DER.integer(1)
            + DER.set(sha256)
            + DER.sequence(DER.oid([1, 2, 840, 113549, 1, 7, 1]))
            + DER.tlv(0xa0, identity.chain.reduce(identity.leaf, +))
            + DER.set(signer))

        return DER.sequence(DER.oid([1, 2, 840, 113549, 1, 7, 2]) + DER.tlv(0xa0, signedData))
    }

    // MARK: Certificates

    /// Reads a .p12. Intermediate certificates come from iDesk's own signature if the .p12 lacks them.
    static func loadIdentity(p12: Data, password: String) throws -> Identity {
        var items: CFArray?
        let status = SecPKCS12Import(p12 as CFData, [kSecImportExportPassphrase as String: password] as CFDictionary, &items)
        guard status == errSecSuccess, let first = (items as? [[String: Any]])?.first,
              let identityRef = first[kSecImportItemIdentity as String] else {
            throw Failure.badCertificate(status == errSecAuthFailed ? String(localized: "wrong password.") : String(localized: "cannot read the .p12 file (code \(String(status)))."))
        }
        let secIdentity = identityRef as! SecIdentity
        var key: SecKey?
        var certificate: SecCertificate?
        guard SecIdentityCopyPrivateKey(secIdentity, &key) == errSecSuccess, let key,
              SecIdentityCopyCertificate(secIdentity, &certificate) == errSecSuccess, let certificate else {
            throw Failure.badCertificate(String(localized: "the .p12 file has no private key."))
        }
        let leaf = SecCertificateCopyData(certificate) as Data
        let fromP12 = ((first[kSecImportItemCertChain as String] as? [SecCertificate]) ?? [])
            .map { SecCertificateCopyData($0) as Data }
        // iOS only accepts a signature that chains to Apple: include the WWDR intermediate and the Apple root.
        // Purchased .p12 files usually lack them, so take them from iDesk's signature and the bundled Apple certificates.
        let chain = AppleCA.chain(for: leaf, candidates: fromP12 + OwnSignature.certificates() + AppleCA.bundled)

        let subject = DER.subjectFields(of: leaf)
        guard let team = subject["OU"], !team.isEmpty else {
            throw Failure.badCertificate(String(localized: "the certificate has no Team ID."))
        }
        return Identity(key: key, leaf: leaf, chain: chain, teamID: team, commonName: subject["CN"] ?? "?")
    }
}

// MARK: - Reading an existing signature from a Mach-O file

/// The signature embedded in an executable / library (iDesk's or a guest app's).
struct EmbeddedSignature {
    let codeDirectory: Data?
    let cms: Data?
    let entitlements: [String: Any]?

    /// nil if the file cannot be read or is not a 64-bit Mach-O.
    init?(executable path: String) {
        guard let file = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) else { return nil }
        var base = 0
        if file.le32(0) == 0xbeba_feca {    // fat file: take the first arm64 slice
            for i in 0..<Int(file.le32(4).byteSwapped) {
                let offset = Int(file.le32(8 + i * 20 + 8).byteSwapped)
                if file.le32(offset) == 0xfeed_facf { base = offset; break }
            }
        }
        guard file.le32(base) == 0xfeed_facf else { return nil }
        var superBlob: Data?
        var p = base + 32
        for _ in 0..<Int(file.le32(base + 16)) {
            let size = Int(file.le32(p + 4))
            if file.le32(p) == 0x1d {
                let start = base + Int(file.le32(p + 8))
                let end = min(file.count, start + Int(file.le32(p + 12)))
                if start < end { superBlob = Data(file[start..<end]) }
                break
            }
            guard size >= 8 else { break }
            p += size
        }
        func blob(_ type: UInt32) -> Data? {
            guard let sb = superBlob, sb.be32(0) == 0xfade_0cc0 else { return nil }
            for i in 0..<Int(sb.be32(8)) where sb.be32(12 + i * 8) == type {
                let offset = Int(sb.be32(16 + i * 8))
                let length = Int(sb.be32(offset + 4))
                guard length >= 8, offset + length <= sb.count else { return nil }
                return Data(sb[offset..<(offset + length)])
            }
            return nil
        }
        codeDirectory = blob(0)
        cms = blob(0x10000)
        // Blob 5: entitlements as an XML plist (after the 8-byte magic + length).
        entitlements = blob(5).flatMap {
            try? PropertyListSerialization.propertyList(from: Data($0.dropFirst(8)), format: nil) as? [String: Any]
        }
    }

    /// The get-task-allow debug entitlement. Only with it does iOS load code from the app's data container.
    var getTaskAllow: Bool? { entitlements?["get-task-allow"] as? Bool }

    var isAdhoc: Bool { (codeDirectory?.be32(12) ?? 0) & 0x2 != 0 }

    var teamID: String? {
        guard let cd = codeDirectory, cd.be32(8) >= 0x20200 else { return nil }
        let offset = Int(cd.be32(48))
        return offset > 0 ? cd.cString(offset, max: 64) : nil
    }

    /// Certificates in the CMS signature. BlobWrapper: magic + length + CMS → SignedData → [0] certificates.
    var certificates: [Data] {
        guard let wrapper = cms, wrapper.count > 8 else { return [] }
        let body = Data(wrapper.dropFirst(8))
        guard let contentInfo = DER.children(of: body).first.map({ DER.children(of: $0.body) }),
              contentInfo.count == 2,
              let signedData = DER.children(of: contentInfo[1].body).first else { return [] }
        let certs = DER.children(of: signedData.body).first { $0.tag == 0xa0 }
        return certs.map { DER.children(of: $0.body).map(\.raw) } ?? []
    }
}

// MARK: - iDesk's own signature

/// Reads the signature ESign / Xcode / SideStore put on iDesk, for its Team ID and certificate chain.
enum OwnSignature {
    /// Must be captured before NSBundle.main is swapped for a guest app (AppDelegate touches it at launch).
    static let executablePath: String = Bundle.main.executablePath ?? CommandLine.arguments[0]

    static let signature = EmbeddedSignature(executable: executablePath)
    static var teamID: String? { signature?.teamID }
    static var getTaskAllow: Bool? { signature?.getTaskAllow }
    static func certificates() -> [Data] { signature?.certificates ?? [] }
}

// MARK: - Minimal DER

enum DER {
    struct Node {
        let tag: UInt8
        let body: Data
        let raw: Data
    }

    static func tlv(_ tag: UInt8, _ body: Data) -> Data {
        var out = Data([tag])
        let n = body.count
        if n < 0x80 {
            out.append(UInt8(n))
        } else {
            let bytes = withUnsafeBytes(of: UInt32(n).bigEndian) { Array($0) }.drop { $0 == 0 }
            out.append(0x80 | UInt8(bytes.count))
            out.append(contentsOf: bytes)
        }
        return out + body
    }

    static func sequence(_ body: Data) -> Data { tlv(0x30, body) }
    static func set(_ body: Data) -> Data { tlv(0x31, body) }
    static func octets(_ body: Data) -> Data { tlv(0x04, body) }
    static func integer(_ value: UInt8) -> Data { tlv(0x02, Data([value])) }
    static let null = Data([0x05, 0x00])

    static func oid(_ parts: [UInt]) -> Data {
        var body = Data([UInt8(parts[0] * 40 + parts[1])])
        for part in parts.dropFirst(2) {
            var groups = [UInt8(part & 0x7f)]
            var rest = part >> 7
            while rest > 0 { groups.insert(UInt8(rest & 0x7f) | 0x80, at: 0); rest >>= 7 }
            body.append(contentsOf: groups)
        }
        return tlv(0x06, body)
    }

    /// Splits the elements that follow each other in `data`.
    static func children(of data: Data) -> [Node] {
        let bytes = [UInt8](data)
        var nodes: [Node] = []
        var i = 0
        while i + 2 <= bytes.count {
            let start = i
            let tag = bytes[i]
            i += 1
            var length = Int(bytes[i])
            i += 1
            if length & 0x80 != 0 {
                let count = length & 0x7f
                guard count > 0, count <= 4, i + count <= bytes.count else { break }
                length = bytes[i..<(i + count)].reduce(0) { $0 << 8 | Int($1) }
                i += count
            }
            guard i + length <= bytes.count else { break }
            nodes.append(Node(tag: tag, body: Data(bytes[i..<(i + length)]), raw: Data(bytes[start..<(i + length)])))
            i += length
        }
        return nodes
    }

    /// tbsCertificate: [0] version, serial, sigAlg, issuer, validity, subject, …
    private static func tbsFields(of certificate: Data) -> [Node] {
        guard let cert = children(of: certificate).first,
              let tbs = children(of: cert.body).first else { return [] }
        var fields = children(of: tbs.body)
        if fields.first?.tag == 0xa0 { fields.removeFirst() }
        return fields
    }

    static func issuerAndSerial(of certificate: Data) throws -> (issuer: Data, serial: Data) {
        let fields = tbsFields(of: certificate)
        guard fields.count >= 3 else { throw CodeSigner.Failure.badCertificate(String(localized: "cannot parse the certificate.")) }
        return (fields[2].raw, fields[0].raw)
    }

    static func issuer(of certificate: Data) -> Data? {
        let fields = tbsFields(of: certificate)
        return fields.count >= 3 ? fields[2].raw : nil
    }

    static func subject(of certificate: Data) -> Data? {
        let fields = tbsFields(of: certificate)
        return fields.count >= 5 ? fields[4].raw : nil
    }

    /// The CN / OU / O fields of the certificate's subject.
    static func subjectFields(of certificate: Data) -> [String: String] {
        let fields = tbsFields(of: certificate)
        guard fields.count >= 5 else { return [:] }
        let names: [Data: String] = [Data([0x55, 0x04, 0x03]): "CN", Data([0x55, 0x04, 0x0b]): "OU", Data([0x55, 0x04, 0x0a]): "O"]
        var out: [String: String] = [:]
        for rdn in children(of: fields[4].body) {
            for pair in children(of: rdn.body) {
                let kv = children(of: pair.body)
                guard kv.count == 2, let name = names[kv[0].body] else { continue }
                out[name] = String(decoding: kv[1].body, as: UTF8.self)
            }
        }
        return out
    }
}

// MARK: - Reading/writing integers in Data

extension Data {
    func le32(_ o: Int) -> UInt32 {
        guard o >= 0, o + 4 <= count else { return 0 }
        return withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt32.self)) }
    }
    func le64(_ o: Int) -> UInt64 {
        guard o >= 0, o + 8 <= count else { return 0 }
        return withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt64.self)) }
    }
    func be32(_ o: Int) -> UInt32 { le32(o).byteSwapped }

    mutating func setLE32(_ o: Int, _ v: UInt32) {
        withUnsafeMutableBytes { $0.storeBytes(of: v.littleEndian, toByteOffset: o, as: UInt32.self) }
    }
    mutating func setLE64(_ o: Int, _ v: UInt64) {
        withUnsafeMutableBytes { $0.storeBytes(of: v.littleEndian, toByteOffset: o, as: UInt64.self) }
    }
    mutating func appendBE32(_ v: UInt32) { Swift.withUnsafeBytes(of: v.bigEndian) { append(contentsOf: $0) } }
    mutating func appendBE64(_ v: UInt64) { Swift.withUnsafeBytes(of: v.bigEndian) { append(contentsOf: $0) } }

    func cString(_ o: Int, max: Int) -> String {
        guard o >= 0, o < count else { return "" }
        let slice = self[(startIndex + o)..<Swift.min(endIndex, startIndex + o + max)]
        return String(decoding: slice.prefix { $0 != 0 }, as: UTF8.self)
    }
}

// MARK: - Bundled Apple certificates

/// Apple's intermediate (WWDR G3, G6) and root certificates - public, taken from Xcode.
/// Used to build a complete certificate chain for the signatures iDesk creates.
enum AppleCA {
    static let bundled: [Data] = {
        let names = ["AppleWWDRCAG3", "AppleWWDRCAG6", "AppleRootCA", "AppleRootCAG3"]
        let bundle = Bundle(url: URL(fileURLWithPath: OwnSignature.executablePath).deletingLastPathComponent())
        return names.compactMap { name in
            (bundle?.url(forResource: name, withExtension: "cer")).flatMap { try? Data(contentsOf: $0) }
        }
    }()

    /// Chain from the signing certificate up to the root (excluding itself): intermediates, then the root.
    static func chain(for leaf: Data, candidates: [Data]) -> [Data] {
        var result: [Data] = []
        var current = leaf
        for _ in 0..<4 {
            guard let issuer = DER.issuer(of: current), issuer != DER.subject(of: current),
                  let parent = candidates.first(where: { $0 != current && !result.contains($0) && DER.subject(of: $0) == issuer })
            else { break }
            result.append(parent)
            current = parent
        }
        return result
    }
}
