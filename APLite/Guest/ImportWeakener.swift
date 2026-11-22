import Foundation

/// Marks system functions that the device's iOS no longer has as "weak" (optional).
///
/// Tweaked apps often carry old libraries (e.g. libsubstrate.dylib from old jailbreaks) that call functions
/// iOS has removed, such as `_dyld_get_all_image_infos`. By default dyld refuses the whole app ("Symbol not found").
/// Marked weak, dyld still loads it and the missing function is bound to NULL; it only fails if the code calls it.
///
/// Marking a function weak that does exist changes nothing (it still binds normally), so a loose check
/// is safe. The patched file loses its signature and must be re-signed (by the signing app or iDesk).
enum ImportWeakener {
    private static let LC_DYLD_INFO: UInt32 = 0x22
    private static let LC_DYLD_INFO_ONLY: UInt32 = 0x8000_0022
    private static let LC_DYLD_CHAINED_FIXUPS: UInt32 = 0x8000_0034
    private static let dylibCommands: Set<UInt32> = [0xc, 0x8000_0018, 0x8000_001f, 0x20, 0x8000_0023]

    /// Whether a function exists in the running system (Mach-O names have a leading "_"), in the library the app
    /// asks for it (`library`): dyld looks it up there, not anywhere. The Simulator's MetricKit lacks a function
    /// another of its libraries has (Facebook's _MXSignpostMetricsSnapshot), so looking everywhere said "there".
    /// Found in another library counts as missing too: marking weak a function that is found changes nothing.
    static func missingOnThisDevice(_ symbol: String, in library: String? = nil) -> Bool {
        guard symbol.hasPrefix("_") else { return false }
        let name = String(symbol.dropFirst())
        guard let library, let handle = libraryHandle(library) else {
            return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) == nil   // RTLD_DEFAULT
        }
        guard let found = dlsym(handle, name) else { return true }
        var info = Dl_info()
        guard dladdr(found, &info) != 0, let file = info.dli_fname else { return false }
        return !String(cString: file).hasSuffix(library)
    }

    private static var handles: [String: UnsafeMutableRawPointer] = [:]
    private static let handlesLock = NSLock()

    private static func libraryHandle(_ path: String) -> UnsafeMutableRawPointer? {
        handlesLock.lock(); defer { handlesLock.unlock() }
        if let h = handles[path] { return h }
        guard let h = dlopen(path, RTLD_LAZY | RTLD_NOLOAD) ?? dlopen(path, RTLD_LAZY) else { return nil }
        handles[path] = h
        return h
    }

    /// System libraries iOS has removed (old tweaks link /usr/lib/libstdc++.6.dylib, gone since iOS 12) would make
    /// dyld refuse the whole app. The load command is pointed at a library every app has (libc++, written over the
    /// old path, which is longer), so the dependency resolves at once; weakenMissingSystemImports, run afterwards,
    /// then makes the functions only the old library had optional. (Marking the command weak instead makes dyld
    /// search for the missing file, and the Simulator's dyld crashes doing so.) Returns the original paths.
    @discardableResult
    static func weakLinkMissingSystemLibraries(at url: URL) throws -> [String] {
        var data = try Data(contentsOf: url)
        guard data.le32(0) == 0xfeed_facf else { return [] }
        var weakened: [String] = []
        var p = 32
        for _ in 0..<Int(data.le32(16)) {
            let cmd = data.le32(p), size = Int(data.le32(p + 4))
            guard size >= 8, p + size <= data.count else { return [] }
            if cmd == 0xc {                                        // LC_LOAD_DYLIB
                let path = data.cString(p + Int(data.le32(p + 8)), max: size)
                let replacement = Array("/usr/lib/libc++.1.dylib".utf8)
                let nameOffset = Int(data.le32(p + 8))
                if (path.hasPrefix("/usr/lib/") || path.hasPrefix("/System/")) && !dlopen_preflight(path),
                   nameOffset + replacement.count < size {
                    for i in nameOffset..<size { data[p + i] = 0 }
                    data.replaceSubrange((p + nameOffset)..<(p + nameOffset + replacement.count), with: replacement)
                    weakened.append(path)
                }
            }
            p += size
        }
        if !weakened.isEmpty { try data.write(to: url, options: .atomic) }
        return weakened
    }

    /// Patches the file (single-architecture 64-bit Mach-O). Returns the names marked weak.
    @discardableResult
    static func weakenMissingSystemImports(at url: URL,
                                           onlySystemLibraries: Bool = true,
                                           isMissing: (String, String?) -> Bool = { missingOnThisDevice($0, in: $1) }) throws -> [String] {
        var data = try Data(contentsOf: url)
        guard data.le32(0) == 0xfeed_facf else { return [] }

        var libraries: [String] = []          // by ordinal 1, 2, 3…
        var opcodeRanges: [Range<Int>] = []   // bind + lazy bind (old style)
        var chained: Range<Int>?
        var p = 32
        for _ in 0..<Int(data.le32(16)) {
            let cmd = data.le32(p), size = Int(data.le32(p + 4))
            guard size >= 8, p + size <= data.count else { return [] }
            if dylibCommands.contains(cmd) {
                libraries.append(data.cString(p + Int(data.le32(p + 8)), max: size))
            } else if cmd == LC_DYLD_INFO || cmd == LC_DYLD_INFO_ONLY {
                for (off, len) in [(16, 20), (32, 36)] {   // bind, lazy bind
                    let start = Int(data.le32(p + off)), count = Int(data.le32(p + len))
                    if count > 0, start + count <= data.count { opcodeRanges.append(start..<(start + count)) }
                }
            } else if cmd == LC_DYLD_CHAINED_FIXUPS {
                let start = Int(data.le32(p + 8)), count = Int(data.le32(p + 12))
                if count > 0, start + count <= data.count { chained = start..<(start + count) }
            }
            p += size
        }

        func isSystem(_ ordinal: Int) -> Bool {
            if !onlySystemLibraries { return ordinal != 0 && ordinal != -1 }
            if ordinal == -2 { return true }                       // flat lookup
            guard ordinal >= 1, ordinal <= libraries.count else { return false }
            let path = libraries[ordinal - 1]
            return path.hasPrefix("/usr/lib/") || path.hasPrefix("/System/")
        }

        // A function iDesk provides is found by the check (in iDesk itself), but the guest asks the system for it.
        let handle: (Int, String) -> Bool = { ord, name in
            guard isSystem(ord) else { return false }
            let library = ord >= 1 && ord <= libraries.count ? libraries[ord - 1] : nil
            return providedByHost.contains(name) || isMissing(name, library)
        }
        var weakened: [String] = []
        for range in opcodeRanges {
            weakened += patchOpcodes(&data, range, shouldWeaken: handle)
        }
        if let chained {
            weakened += patchChainedImports(&data, chained, shouldWeaken: handle)
        }
        if !weakened.isEmpty { try data.write(to: url, options: .atomic) }
        return weakened
    }

    // MARK: Bind opcode (LC_DYLD_INFO)

    private struct Op {
        let opcode: UInt8
        let imm: UInt8
        let position: Int
        let name: String?
    }

    /// Decodes a bind stream into a list of opcodes (keeping byte offsets for patching).
    private static func decode(_ data: Data, _ range: Range<Int>) -> [Op] {
        var ops: [Op] = []
        var i = range.lowerBound
        func uleb() {
            while i < range.upperBound { let b = data[i]; i += 1; if b & 0x80 == 0 { break } }
        }
        while i < range.upperBound {
            let byte = data[i], position = i
            let opcode = byte & 0xF0, imm = byte & 0x0F
            i += 1
            var name: String?
            switch opcode {
            case 0x00, 0x10, 0x30, 0x50, 0x90, 0xB0: break
            case 0x20, 0x60, 0x70, 0x80, 0xA0: uleb()
            case 0x40:
                name = data.cString(i, max: range.upperBound - i)
                i += name!.utf8.count + 1
            case 0xC0: uleb(); uleb()
            case 0xD0: if imm == 0 { uleb() }
            default: return ops                                    // unknown opcode: stop, do not guess
            }
            ops.append(Op(opcode: opcode, imm: imm, position: position, name: name))
        }
        return ops
    }

    private static func patchOpcodes(_ data: inout Data, _ range: Range<Int>,
                                     shouldWeaken: (Int, String) -> Bool) -> [String] {
        let ops = decode(data, range)
        var result: [String] = []
        var ordinal = 0
        var ordinalOp: Int?            // index of the most recent library-ordinal opcode (in ops)
        var symbolsSinceOrdinal = 0
        for (index, op) in ops.enumerated() {
            switch op.opcode {
            case 0x10: ordinal = Int(op.imm); ordinalOp = index; symbolsSinceOrdinal = 0
            case 0x20:
                var v = 0, shift = 0, k = op.position + 1
                while k < range.upperBound { let b = data[k]; k += 1; v |= Int(b & 0x7f) << shift; shift += 7; if b & 0x80 == 0 { break } }
                ordinal = v; ordinalOp = index; symbolsSinceOrdinal = 0
            case 0x30: ordinal = op.imm == 0 ? 0 : Int(Int8(bitPattern: 0xF0 | op.imm)); ordinalOp = index; symbolsSinceOrdinal = 0
            case 0x40:
                guard let name = op.name else { break }
                defer { symbolsSinceOrdinal += 1 }
                guard op.imm & 0x1 == 0, shouldWeaken(ordinal, name) else { break }
                data[op.position] |= 0x1                            // BIND_SYMBOL_FLAGS_WEAK_IMPORT
                result.append(name)
                // A function iDesk provides itself: switch the source library to flat lookup so dyld finds it in iDesk.
                // Only when that ordinal opcode is used by this symbol alone (so no other symbol is affected).
                guard providedByHost.contains(name), symbolsSinceOrdinal == 0,
                      let ordIndex = ordinalOp, ops[ordIndex].opcode != 0x20 else { break }
                let next = ops[(index + 1)...].first { $0.opcode == 0x40 || [0x10, 0x20, 0x30].contains($0.opcode) }
                let exclusive = next == nil || next!.opcode != 0x40
                if exclusive {
                    data[ops[ordIndex].position] = 0x30 | 0x0E          // SET_DYLIB_SPECIAL_IMM(-2) = flat lookup
                }
            default: break
            }
        }
        return result
    }

    /// Functions that iDesk provides itself (GuestCompat.c).
    static let providedByHost: Set<String> = ["__dyld_get_all_image_infos"]

    // MARK: Chained fixups (LC_DYLD_CHAINED_FIXUPS)

    private static func patchChainedImports(_ data: inout Data, _ range: Range<Int>,
                                            shouldWeaken: (Int, String) -> Bool) -> [String] {
        let base = range.lowerBound
        let importsOffset = Int(data.le32(base + 8))
        let symbolsOffset = Int(data.le32(base + 12))
        let count = Int(data.le32(base + 16))
        let format = data.le32(base + 20)
        guard data.le32(base + 24) == 0 else { return [] }       // compressed names: not supported
        let stride: Int
        switch format {
        case 1: stride = 4
        case 2: stride = 8
        case 3: stride = 16
        default: return []
        }
        var result: [String] = []
        for n in 0..<count {
            let at = base + importsOffset + n * stride
            guard at + stride <= range.upperBound else { break }
            let ordinal: Int, weak: Bool, nameOffset: Int
            if format == 3 {
                let v = data.le64(at)
                let raw = Int(v & 0xFFFF)
                ordinal = raw >= 0xFFF0 ? raw - 0x10000 : raw     // only the last values are special (-1, -2, -3)
                weak = (v >> 16) & 1 == 1
                nameOffset = Int(v >> 32)
            } else {
                let v = data.le32(at)
                let raw = Int(v & 0xFF)
                ordinal = raw >= 0xF0 ? raw - 0x100 : raw         // libraries 128…239 are not special (Facebook has 140)
                weak = (v >> 8) & 1 == 1
                nameOffset = Int(v >> 9)
            }
            guard !weak else { continue }
            let name = data.cString(base + symbolsOffset + nameOffset, max: range.upperBound - base - symbolsOffset - nameOffset)
            guard shouldWeaken(ordinal, name) else { continue }
            let flat = providedByHost.contains(name)   // bind to the function iDesk provides (flat lookup)
            if format == 3 {
                var v = data.le64(at) | (1 << 16)
                if flat { v = (v & ~0xFFFF) | 0xFFFE }
                data.setLE64(at, v)
            } else {
                var v = data.le32(at) | (1 << 8)
                if flat { v = (v & ~0xFF) | 0xFE }
                data.setLE32(at, v)
            }
            result.append(name)
        }
        return result
    }
}
