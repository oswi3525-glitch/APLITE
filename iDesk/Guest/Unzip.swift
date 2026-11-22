import Foundation
import Compression

/// Minimal ZIP extractor (enough for .ipa files): stored + deflate, ZIP64 and symlinks.
enum Unzip {
    enum Failure: LocalizedError {
        case notZip
        case unsupported(String)
        case corrupt(String)

        var errorDescription: String? {
            switch self {
            case .notZip: return String(localized: "The file is not a ZIP/IPA.")
            case .unsupported(let s): return String(localized: "The ZIP uses an unsupported feature: \(s).")
            case .corrupt(let s): return String(localized: "The ZIP file is damaged: \(s).")
            }
        }
    }

    static func extract(_ archive: URL, to destination: URL) throws {
        let data = try Data(contentsOf: archive, options: .alwaysMapped)
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let root = destination.standardizedFileURL.path

        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let zip = Reader(raw)
            let (cdOffset, entryCount) = try zip.centralDirectory()
            var p = cdOffset
            for _ in 0..<entryCount {
                guard zip.u32(p) == 0x0201_4b50 else { throw Failure.corrupt(String(localized: "central directory")) }
                let flags = zip.u16(p + 8)
                let method = zip.u16(p + 10)
                var compressedSize = UInt64(zip.u32(p + 20))
                var size = UInt64(zip.u32(p + 24))
                let nameLength = Int(zip.u16(p + 28))
                let extraLength = Int(zip.u16(p + 30))
                let commentLength = Int(zip.u16(p + 32))
                let mode = zip.u32(p + 38) >> 16
                var localOffset = UInt64(zip.u32(p + 42))
                let name = zip.string(p + 46, nameLength)

                // ZIP64 extra field
                var e = p + 46 + nameLength
                let extraEnd = e + extraLength
                while e + 4 <= extraEnd {
                    let id = zip.u16(e), len = Int(zip.u16(e + 2))
                    if id == 0x0001 {
                        var q = e + 4
                        if size == 0xFFFF_FFFF { size = zip.u64(q); q += 8 }
                        if compressedSize == 0xFFFF_FFFF { compressedSize = zip.u64(q); q += 8 }
                        if localOffset == 0xFFFF_FFFF { localOffset = zip.u64(q) }
                    }
                    e += 4 + len
                }
                p = extraEnd + commentLength

                if flags & 1 != 0 { throw Failure.unsupported(String(localized: "password encryption")) }
                if name.hasPrefix("__MACOSX/") { continue }
                // Reject paths that escape the destination folder.
                let parts = name.split(separator: "/", omittingEmptySubsequences: true)
                if name.hasPrefix("/") || parts.contains("..") || parts.isEmpty { continue }
                let target = destination.appendingPathComponent(parts.joined(separator: "/"))
                guard target.standardizedFileURL.path.hasPrefix(root) else { continue }

                if name.hasSuffix("/") {
                    try fm.createDirectory(at: target, withIntermediateDirectories: true)
                    continue
                }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

                let lo = Int(localOffset)
                guard zip.u32(lo) == 0x0403_4b50 else { throw Failure.corrupt(name) }
                let start = lo + 30 + Int(zip.u16(lo + 26)) + Int(zip.u16(lo + 28))
                guard start + Int(compressedSize) <= raw.count else { throw Failure.corrupt(name) }
                let body = UnsafeRawBufferPointer(rebasing: raw[start..<(start + Int(compressedSize))])

                if mode & 0xF000 == 0xA000 {
                    // Symlink: the content is the target path. Only relative targets that stay inside are accepted.
                    let link = try String(decoding: inflateAll(body, method: method, size: Int(size)), as: UTF8.self)
                    if link.hasPrefix("/") || link.split(separator: "/").contains("..") { continue }
                    try? fm.removeItem(at: target)
                    try fm.createSymbolicLink(atPath: target.path, withDestinationPath: link)
                    continue
                }

                fm.createFile(atPath: target.path, contents: nil)
                let handle = try FileHandle(forWritingTo: target)
                defer { try? handle.close() }
                switch method {
                case 0: try handle.write(contentsOf: Data(body))
                case 8: try inflate(body) { try handle.write(contentsOf: $0) }
                default: throw Failure.unsupported(String(localized: "compression method \(String(method))"))
                }
                if mode & 0o111 != 0 {
                    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
                }
            }
        }
    }

    /// Entry names in a ZIP file, without extracting (to tell an IPA from a certificate zip).
    static func entryNames(_ archive: URL) throws -> [String] {
        let data = try Data(contentsOf: archive, options: .alwaysMapped)
        return try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let zip = Reader(raw)
            let (offset, count) = try zip.centralDirectory()
            var names: [String] = []
            var p = offset
            for _ in 0..<count {
                guard zip.u32(p) == 0x0201_4b50 else { throw Failure.corrupt(String(localized: "central directory")) }
                let nameLength = Int(zip.u16(p + 28))
                names.append(zip.string(p + 46, nameLength))
                p += 46 + nameLength + Int(zip.u16(p + 30)) + Int(zip.u16(p + 32))
            }
            return names
        }
    }

    private static func inflateAll(_ body: UnsafeRawBufferPointer, method: UInt16, size: Int) throws -> Data {
        if method == 0 { return Data(body) }
        var out = Data(capacity: size)
        try inflate(body) { out.append($0) }
        return out
    }

    /// Inflates raw deflate in chunks so large files do not use much memory.
    private static func inflate(_ body: UnsafeRawBufferPointer, sink: (Data) throws -> Void) throws {
        guard let base = body.bindMemory(to: UInt8.self).baseAddress, !body.isEmpty else { return }
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw Failure.corrupt(String(localized: "cannot start the decompressor"))
        }
        defer { compression_stream_destroy(stream) }

        let chunk = 256 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { buffer.deallocate() }
        stream.pointee.src_ptr = base
        stream.pointee.src_size = body.count
        while true {
            stream.pointee.dst_ptr = buffer
            stream.pointee.dst_size = chunk
            let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
            let produced = chunk - stream.pointee.dst_size
            if produced > 0 { try sink(Data(bytes: buffer, count: produced)) }
            if status == COMPRESSION_STATUS_END { return }
            if status != COMPRESSION_STATUS_OK || (produced == 0 && stream.pointee.src_size == 0) {
                throw Failure.corrupt(String(localized: "compressed data"))
            }
        }
    }

    private struct Reader {
        let raw: UnsafeRawBufferPointer
        init(_ raw: UnsafeRawBufferPointer) { self.raw = raw }

        func u16(_ o: Int) -> UInt16 {
            guard o >= 0, o + 2 <= raw.count else { return 0 }
            return UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: UInt16.self))
        }
        func u32(_ o: Int) -> UInt32 {
            guard o >= 0, o + 4 <= raw.count else { return 0 }
            return UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: UInt32.self))
        }
        func u64(_ o: Int) -> UInt64 {
            guard o >= 0, o + 8 <= raw.count else { return 0 }
            return UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: UInt64.self))
        }
        func string(_ o: Int, _ n: Int) -> String {
            guard o >= 0, n >= 0, o + n <= raw.count else { return "" }
            return String(decoding: UnsafeRawBufferPointer(rebasing: raw[o..<(o + n)]), as: UTF8.self)
        }

        /// Returns (central directory offset, entry count).
        func centralDirectory() throws -> (Int, Int) {
            guard raw.count >= 22 else { throw Failure.notZip }
            var eocd = raw.count - 22
            let lowest = max(0, raw.count - 22 - 0xFFFF)
            while eocd >= lowest, u32(eocd) != 0x0605_4b50 { eocd -= 1 }
            guard eocd >= lowest else { throw Failure.notZip }

            var count = UInt64(u16(eocd + 10))
            var offset = UInt64(u32(eocd + 16))
            if count == 0xFFFF || offset == 0xFFFF_FFFF, eocd >= 20, u32(eocd - 20) == 0x0706_4b50 {
                let z = Int(u64(eocd - 20 + 8))
                guard u32(z) == 0x0606_4b50 else { throw Failure.corrupt("ZIP64") }
                count = u64(z + 32)
                offset = u64(z + 48)
            }
            guard offset < UInt64(raw.count) else { throw Failure.corrupt(String(localized: "central directory")) }
            return (Int(offset), Int(count))
        }
    }
}
