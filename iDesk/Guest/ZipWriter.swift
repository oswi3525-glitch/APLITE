import Foundation
import Compression
import zlib

/// Writes ZIP files (enough to build an .ipa for signing apps). Deflate-compressed; stored when compression does not help.
/// Reads in chunks, so guest apps of several hundred MB do not use much memory. ZIP64 for large files.
final class ZipWriter {
    private struct Entry {
        let name: [UInt8]
        let crc: UInt32
        let size: UInt64
        let compressedSize: UInt64
        let method: UInt16
        let offset: UInt64
        let mode: UInt16
        let isDirectory: Bool
    }

    private let handle: FileHandle
    private let scratch: URL
    private var entries: [Entry] = []
    private var offset: UInt64 = 0
    private let chunk = 1 << 20

    init(creating url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        scratch = url.deletingLastPathComponent().appendingPathComponent(".zip-\(UUID().uuidString).tmp")
    }

    /// Total uncompressed bytes added so far (for progress by data processed).
    private(set) var bytesRead: UInt64 = 0

    /// Adds a whole folder; paths inside the zip start with `prefix` (e.g. "Payload/iDesk.app").
    /// `skip`: relative paths to leave out (a skipped folder drops its contents too).
    /// `replace`: substitutes another file for a relative path.
    func addDirectory(_ directory: URL, as prefix: String,
                      skip: (String) -> Bool = { _ in false },
                      replace: [String: URL] = [:],
                      progress: ((UInt64) -> Void)? = nil) throws {
        let fm = FileManager.default
        try addEntry(name: prefix + "/", file: nil, mode: 0o755)
        guard let walker = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
        let base = directory.standardizedFileURL.path
        for case let url as URL in walker {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base) else { continue }
            let relative = String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { continue }   // iOS bundles practically never contain symlinks
            if skip(relative) {
                if values.isDirectory == true { walker.skipDescendants() }
                continue
            }
            if values.isDirectory == true {
                try addEntry(name: prefix + "/" + relative + "/", file: nil, mode: 0o755)
            } else {
                let source = replace[relative] ?? url
                try addEntry(name: prefix + "/" + relative, file: source, mode: MachOPatcher.isMachO(source) ? 0o755 : 0o644)
                progress?(bytesRead)
            }
        }
    }

    func addEntry(name: String, file: URL?, mode: UInt16) throws {
        let nameBytes = Array(name.utf8)
        var crc: UInt32 = 0
        var size: UInt64 = 0
        var compressedSize: UInt64 = 0
        var method: UInt16 = 0
        var payload: URL?                       // data copied into the zip (temporary compressed file or the original)

        if let file {
            // One pass: CRC, size, and the compressed copy in a temporary file.
            let reader = try FileHandle(forReadingFrom: file)
            defer { try? reader.close() }
            var c = crc32(0, nil, 0)
            FileManager.default.createFile(atPath: scratch.path, contents: nil)
            let encoder = try DeflateStream(output: try FileHandle(forWritingTo: scratch), chunk: chunk)
            while let data = try reader.read(upToCount: chunk), !data.isEmpty {
                c = data.withUnsafeBytes { crc32(c, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)) }
                size += UInt64(data.count)
                try encoder.write(data)
            }
            crc = UInt32(c)
            bytesRead += size
            compressedSize = try encoder.finish()
            if compressedSize < size {
                method = 8
                payload = scratch
            } else {
                compressedSize = size        // compression does not help: store
                payload = file
            }
        }

        let entry = Entry(name: nameBytes, crc: crc, size: size, compressedSize: compressedSize,
                          method: method, offset: offset, mode: mode, isDirectory: file == nil)
        let zip64 = size >= 0xFFFF_FFFF || compressedSize >= 0xFFFF_FFFF || offset >= 0xFFFF_FFFF

        var header = Data()
        header.putLE32(0x0403_4b50)
        header.putLE16(zip64 ? 45 : 20)                  // version needed
        header.putLE16(0x0800)                           // UTF-8 file names
        header.putLE16(method)
        header.putLE16(0); header.putLE16(0x21)          // time, date (1980-01-01)
        header.putLE32(crc)
        header.putLE32(zip64 ? 0xFFFF_FFFF : UInt32(compressedSize))
        header.putLE32(zip64 ? 0xFFFF_FFFF : UInt32(size))
        header.putLE16(UInt16(nameBytes.count))
        header.putLE16(zip64 ? 20 : 0)
        header.append(contentsOf: nameBytes)
        if zip64 {
            header.putLE16(0x0001); header.putLE16(16)
            header.putLE64(size); header.putLE64(compressedSize)
        }
        try write(header)

        if let payload {
            let reader = try FileHandle(forReadingFrom: payload)
            defer { try? reader.close() }
            while let data = try reader.read(upToCount: chunk), !data.isEmpty { try write(data) }
        }
        try? FileManager.default.removeItem(at: scratch)
        entries.append(entry)
    }

    func finish() throws {
        let cdStart = offset
        for e in entries {
            let big = e.size >= 0xFFFF_FFFF || e.compressedSize >= 0xFFFF_FFFF || e.offset >= 0xFFFF_FFFF
            var cd = Data()
            cd.putLE32(0x0201_4b50)
            cd.putLE16(0x0300 | 45)                      // made on "Unix" to keep file permissions
            cd.putLE16(big ? 45 : 20)
            cd.putLE16(0x0800)
            cd.putLE16(e.method)
            cd.putLE16(0); cd.putLE16(0x21)
            cd.putLE32(e.crc)
            cd.putLE32(big ? 0xFFFF_FFFF : UInt32(e.compressedSize))
            cd.putLE32(big ? 0xFFFF_FFFF : UInt32(e.size))
            cd.putLE16(UInt16(e.name.count))
            cd.putLE16(big ? 28 : 0)
            cd.putLE16(0); cd.putLE16(0); cd.putLE16(0)
            let type: UInt32 = e.isDirectory ? 0o040000 : 0o100000
            cd.putLE32(((type | UInt32(e.mode)) << 16) | (e.isDirectory ? 0x10 : 0))
            cd.putLE32(big ? 0xFFFF_FFFF : UInt32(e.offset))
            cd.append(contentsOf: e.name)
            if big {
                cd.putLE16(0x0001); cd.putLE16(24)
                cd.putLE64(e.size); cd.putLE64(e.compressedSize); cd.putLE64(e.offset)
            }
            try write(cd)
        }
        let cdSize = offset - cdStart
        let count = UInt64(entries.count)
        let needs64 = count >= 0xFFFF || cdStart >= 0xFFFF_FFFF || cdSize >= 0xFFFF_FFFF
        if needs64 {
            let z64 = offset
            var r = Data()
            r.putLE32(0x0606_4b50); r.putLE64(44)
            r.putLE16(45); r.putLE16(45); r.putLE32(0); r.putLE32(0)
            r.putLE64(count); r.putLE64(count); r.putLE64(cdSize); r.putLE64(cdStart)
            r.putLE32(0x0706_4b50); r.putLE32(0); r.putLE64(z64); r.putLE32(1)
            try write(r)
        }
        var end = Data()
        end.putLE32(0x0605_4b50)
        end.putLE16(0); end.putLE16(0)
        end.putLE16(needs64 ? 0xFFFF : UInt16(count)); end.putLE16(needs64 ? 0xFFFF : UInt16(count))
        end.putLE32(needs64 ? 0xFFFF_FFFF : UInt32(cdSize))
        end.putLE32(needs64 ? 0xFFFF_FFFF : UInt32(cdStart))
        end.putLE16(0)
        try write(end)
        try handle.close()
        try? FileManager.default.removeItem(at: scratch)
    }

    private func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
        offset += UInt64(data.count)
    }
}

/// Raw deflate (the format ZIP needs) in chunks, written straight to a file.
private final class DeflateStream {
    private let output: FileHandle
    private let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
    private let buffer: UnsafeMutablePointer<UInt8>
    private let size: Int
    private var written: UInt64 = 0

    init(output: FileHandle, chunk: Int) throws {
        self.output = output
        size = chunk
        buffer = .allocate(capacity: chunk)
        // Apple's COMPRESSION_ZLIB is raw deflate (no zlib header) - exactly what ZIP uses.
        guard compression_stream_init(stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    deinit {
        compression_stream_destroy(stream)
        stream.deallocate()
        buffer.deallocate()
    }

    func write(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = raw.count
            try pump(finalize: false)
        }
    }

    /// Closes the stream; returns the number of compressed bytes.
    func finish() throws -> UInt64 {
        stream.pointee.src_size = 0
        try pump(finalize: true)
        try output.close()
        return written
    }

    private func pump(finalize: Bool) throws {
        repeat {
            stream.pointee.dst_ptr = buffer
            stream.pointee.dst_size = size
            let status = compression_stream_process(stream, finalize ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
            guard status != COMPRESSION_STATUS_ERROR else { throw CocoaError(.fileWriteUnknown) }
            let produced = size - stream.pointee.dst_size
            if produced > 0 {
                try output.write(contentsOf: Data(bytes: buffer, count: produced))
                written += UInt64(produced)
            }
            if finalize && status == COMPRESSION_STATUS_END { return }
        } while stream.pointee.src_size > 0 || (finalize && stream.pointee.dst_size == 0) || finalize
    }
}

private extension Data {
    mutating func putLE16(_ v: UInt16) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func putLE32(_ v: UInt32) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func putLE64(_ v: UInt64) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
}
