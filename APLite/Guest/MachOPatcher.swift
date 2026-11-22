import Foundation

/// Patches a guest app's executable so `dlopen` can load it as a library.
///
/// iOS will not `dlopen` an MH_EXECUTE file, so:
/// 1. change the file type to MH_DYLIB,
/// 2. shrink `__PAGEZERO` (4 GB), since a library may not claim that address range,
/// 3. rewrite `@executable_path` to `@loader_path` so the app finds its own Frameworks folder
///    (inside iDesk, `@executable_path` points at iDesk, not the guest app).
///
/// This invalidates the file's old signature; on a device it must be re-signed with iDesk's certificate.
enum MachOPatcher {
    enum Failure: LocalizedError {
        case notMachO
        case encrypted
        case noArm64
        case noRoomForID

        var errorDescription: String? {
            switch self {
            case .notMachO: return String(localized: "The app’s executable is not a 64-bit Mach-O.")
            case .encrypted: return String(localized: "The app is still FairPlay-encrypted (an IPA straight from the App Store). APLite can only load decrypted IPAs.")
            case .noArm64: return String(localized: "The app has no arm64 slice.")
            case .noRoomForID: return String(localized: "The app’s executable has an unusual layout (no LC_LOAD_DYLINKER) and cannot be patched.")
            }
        }
    }

    private static let MH_MAGIC_64: UInt32 = 0xfeed_facf
    private static let FAT_MAGIC_BE: UInt32 = 0xbeba_feca      // 0xcafebabe read as little-endian
    private static let FAT_MAGIC_64_BE: UInt32 = 0xbfba_feca
    private static let MH_EXECUTE: UInt32 = 2
    private static let MH_DYLIB: UInt32 = 6
    private static let MH_NO_REEXPORTED_DYLIBS: UInt32 = 0x10_0000
    private static let MH_PIE: UInt32 = 0x20_0000
    private static let LC_SEGMENT_64: UInt32 = 0x19
    private static let LC_ENCRYPTION_INFO_64: UInt32 = 0x2c
    private static let LC_RPATH: UInt32 = 0x8000_001c
    private static let LC_ID_DYLIB: UInt32 = 0xd
    private static let LC_LOAD_DYLINKER: UInt32 = 0xe
    private static let dylibCommands: Set<UInt32> = [0xc, 0x8000_0018, 0x8000_001f, 0x20, 0x8000_0023]

    /// Whether the file is Mach-O (single or multi-architecture) - reads only the first 4 bytes.
    static func isMachO(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
        let magic = head.le32(0)
        return magic == MH_MAGIC_64 || magic == FAT_MAGIC_BE || magic == FAT_MAGIC_64_BE
    }

    /// Patches in place. Running it again on a patched file is harmless.
    static func patchExecutable(at url: URL) throws {
        try thin(at: url)
        var data = try Data(contentsOf: url)
        guard data.le32(0) == MH_MAGIC_64 else { throw Failure.notMachO }
        try patchSlice(&data, 0)
        try data.write(to: url, options: .atomic)
    }

    /// Fat (multi-architecture) file: keep only the arm64 slice, to patch and sign it simply.
    static func thin(at url: URL) throws {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        let magic = data.le32(0)
        guard magic == FAT_MAGIC_BE || magic == FAT_MAGIC_64_BE else { return }
        let is64 = magic == FAT_MAGIC_64_BE
        var best: (offset: Int, size: Int, subtype: UInt32)?
        for i in 0..<Int(data.be32(4)) {
            let entry = 8 + i * (is64 ? 32 : 20)
            guard data.be32(entry) == 0x0100_000c else { continue }        // CPU_TYPE_ARM64
            let subtype = data.be32(entry + 4) & 0x00ff_ffff
            let offset = is64 ? Int(data.le64(entry + 8).byteSwapped) : Int(data.be32(entry + 8))
            let size = is64 ? Int(data.le64(entry + 16).byteSwapped) : Int(data.be32(entry + 12))
            guard offset + size <= data.count, data.le32(offset) == MH_MAGIC_64 else { continue }
            // Prefer plain arm64 (subtype 0); arm64e (2) cannot load into an arm64 process.
            if best == nil || subtype < best!.subtype { best = (offset, size, subtype) }
        }
        guard let slice = best else { throw Failure.noArm64 }
        try Data(data[slice.offset..<(slice.offset + slice.size)]).write(to: url, options: .atomic)
    }

    private static func patchSlice(_ data: inout Data, _ base: Int) throws {
        if data.le32(base + 12) == MH_EXECUTE {
            data.setLE32(base + 12, MH_DYLIB)
            data.setLE32(base + 24, (data.le32(base + 24) | MH_NO_REEXPORTED_DYLIBS) & ~MH_PIE)
        }
        let commandCount = Int(data.le32(base + 16))
        var p = base + 32
        var hasID = false
        var dylinker = -1
        for _ in 0..<commandCount {
            let cmd = data.le32(p)
            let size = Int(data.le32(p + 4))
            guard size >= 8, p + size <= data.count else { throw Failure.notMachO }

            switch cmd {
            case LC_SEGMENT_64:
                // segname @8 (16 byte), vmaddr @24, vmsize @32
                if data.cString(p + 8, max: 16) == "__PAGEZERO", data.le64(p + 24) == 0, data.le64(p + 32) == 0x1_0000_0000 {
                    data.setLE64(p + 24, 0x1_0000_0000 - 0x4000)
                    data.setLE64(p + 32, 0x4000)
                }
            case LC_ENCRYPTION_INFO_64:
                if data.le32(p + 16) != 0 { throw Failure.encrypted }   // cryptid
            case LC_ID_DYLIB:
                hasID = true
            case LC_LOAD_DYLINKER:
                if size >= 32 { dylinker = p }
            case LC_RPATH:
                rewritePrefix(&data, command: p, size: size, from: "@executable_path", to: "@loader_path")
            case _ where dylibCommands.contains(cmd):
                rewritePrefix(&data, command: p, size: size, from: "@executable_path", to: "@loader_path")
            default:
                break
            }
            p += size
        }

        // dyld requires an install name (LC_ID_DYLIB) for libraries, otherwise it reads a null pointer.
        // Every executable has LC_LOAD_DYLINKER ("/usr/lib/dyld"), which a library does not need,
        // so turn that command into LC_ID_DYLIB: no bytes need to be inserted.
        if !hasID {
            guard dylinker >= 0 else { throw Failure.noRoomForID }
            let size = Int(data.le32(dylinker + 4))
            data.setLE32(dylinker, LC_ID_DYLIB)
            data.setLE32(dylinker + 8, 24)              // offset of the name in the command
            data.setLE32(dylinker + 12, 2)              // timestamp
            data.setLE32(dylinker + 16, 0x1_0000)       // current version 1.0
            data.setLE32(dylinker + 20, 0x1_0000)       // compatibility version 1.0
            let name = Array("guest".utf8)
            for i in 0..<(size - 24) { data[dylinker + 24 + i] = i < name.count ? name[i] : 0 }
        }
    }

    /// Rewrites a path prefix in an LC_RPATH / LC_LOAD_DYLIB command. Only when the new string is not longer.
    private static func rewritePrefix(_ data: inout Data, command p: Int, size: Int, from: String, to: String) {
        let stringOffset = Int(data.le32(p + 8))
        guard stringOffset > 0, stringOffset < size else { return }
        let start = p + stringOffset
        let capacity = size - stringOffset
        let path = data.cString(start, max: capacity)
        guard path.hasPrefix(from) else { return }
        let bytes = Array((to + path.dropFirst(from.count)).utf8)
        guard bytes.count < capacity else { return }
        for i in 0..<capacity { data[start + i] = i < bytes.count ? bytes[i] : 0 }
    }

    /// A guest app's framework (not its executable) that finds the app's other frameworks through
    /// "@executable_path/Frameworks": inside iDesk that is iDesk's folder, so a framework the app opens later
    /// (Facebook's FBRarelyUsedFramework) does not find FBSharedFramework and the app stops. `replacement` names the
    /// same folder from the framework itself ("@loader_path/.." for Frameworks/X.framework/X), which stays right
    /// once the frameworks are moved into iDesk.app/Frameworks. Returns whether the file changed.
    @discardableResult
    static func pointExecutablePath(at url: URL, to replacement: String) throws -> Bool {
        var data = try Data(contentsOf: url)
        guard data.le32(0) == MH_MAGIC_64 else { return false }
        let original = data
        var p = 32
        for _ in 0..<Int(data.le32(16)) {
            let cmd = data.le32(p), size = Int(data.le32(p + 4))
            guard size >= 8, p + size <= data.count else { return false }
            if cmd == LC_RPATH || dylibCommands.contains(cmd) {
                rewritePrefix(&data, command: p, size: size, from: "@executable_path/Frameworks", to: replacement)
            }
            p += size
        }
        guard data != original else { return false }
        try data.write(to: url, options: .atomic)
        return true
    }

    /// When a guest app is bundled into iDesk (export for the signing app), its frameworks sit next to it in
    /// iDesk.app/Frameworks instead of nested inside, so "@loader_path/Frameworks/…" → "@loader_path/../…".
    /// Writes a new file; the original is left untouched.
    static func relocateFrameworks(from source: URL, to destination: URL) throws {
        var data = try Data(contentsOf: source)
        guard data.le32(0) == MH_MAGIC_64 else { throw Failure.notMachO }
        var p = 32
        for _ in 0..<Int(data.le32(16)) {
            let cmd = data.le32(p), size = Int(data.le32(p + 4))
            guard size >= 8, p + size <= data.count else { throw Failure.notMachO }
            if cmd == LC_RPATH || dylibCommands.contains(cmd) {
                rewritePrefix(&data, command: p, size: size, from: "@loader_path/Frameworks", to: "@loader_path/..")
            }
            p += size
        }
        try data.write(to: destination, options: .atomic)
    }
}
