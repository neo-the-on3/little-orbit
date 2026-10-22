import Foundation
import LittleOrbitDomain

#if canImport(AppleArchive)
    import AppleArchive
    import System

    /// The exported `.littleorbit-backup` file: one backup folder in an uncompressed Apple Archive, the system
    /// framework, with no new dependency (D195a.1). Nothing is ever extracted: reading a picked file streams it from
    /// where it is and writes nothing anywhere (D197a.1). Reading lists the entries and reads only the bytes asked
    /// for, in fixed-size chunks when streamed, so the manifest can be checked before anything else and no
    /// attachment is held while checking (B1.1).
    public struct AppleArchiveBackupArchiving: BackupArchiving {
        private static var type: ArchiveHeader.FieldKey { ArchiveHeader.FieldKey("TYP") }
        private static var path: ArchiveHeader.FieldKey { ArchiveHeader.FieldKey("PAT") }
        private static var link: ArchiveHeader.FieldKey { ArchiveHeader.FieldKey("LNK") }
        private static var mode: ArchiveHeader.FieldKey { ArchiveHeader.FieldKey("MOD") }
        private static var data: ArchiveHeader.FieldKey { ArchiveHeader.FieldKey("DAT") }
        /// Present on entries that are hard links to one another.
        private static var hardLinkCluster: ArchiveHeader.FieldKey { ArchiveHeader.FieldKey("HLC") }
        /// A link count, as cpio-style archives record it.
        private static var linkCount: ArchiveHeader.FieldKey { ArchiveHeader.FieldKey("NLK") }

        public init() {}

        public func archive(_ files: BackupSnapshotFiles) throws -> Data {
            let memory = MemoryByteStream()
            guard let stream = ArchiveByteStream.customStream(instance: memory) else {
                throw CocoaError(.fileWriteUnknown)
            }
            defer { try? stream.close() }
            guard let encoder = ArchiveStream.encodeStream(writingTo: stream) else {
                throw CocoaError(.fileWriteUnknown)
            }
            // The manifest comes first, so a reader reaches the format version before any other entry (L34).
            let others = files.paths.filter { $0 != BackupFormat.manifestPath }
            if let manifest = files[BackupFormat.manifestPath] {
                try Self.writeFile(BackupFormat.manifestPath, manifest, to: encoder)
            }
            for folder in Self.folders(of: others) {
                try Self.writeFolder(folder, to: encoder)
            }
            for path in others {
                try Self.writeFile(path, files[path] ?? Data(), to: encoder)
            }
            try encoder.close()
            try stream.close()
            return memory.data
        }

        /// Streams the archive into a new file at `url`: each file's header with its listed size, then its bytes
        /// with one `writeBlob` call per chunk from `folder`, so no file is held whole (B2). The manifest is the
        /// caller's first file (L34).
        public func archive(_ files: [BackupArchiveFile], from folder: any BackupFileReading, to url: URL) throws {
            guard
                let stream = ArchiveByteStream.fileStream(
                    path: FilePath(url.path),
                    mode: .writeOnly,
                    options: [.create, .exclusiveCreate],
                    permissions: FilePermissions(rawValue: 0o600),
                )
            else {
                throw CocoaError(.fileWriteUnknown)
            }
            defer { try? stream.close() }
            guard let encoder = ArchiveStream.encodeStream(writingTo: stream) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let others = files.filter { $0.path != BackupFormat.manifestPath }
            for file in files where file.path == BackupFormat.manifestPath {
                try Self.streamFile(file, from: folder, to: encoder)
            }
            for path in Self.folders(of: others.map(\.path)) {
                try Self.writeFolder(path, to: encoder)
            }
            for file in others {
                try Self.streamFile(file, from: folder, to: encoder)
            }
            try encoder.close()
            try stream.close()
        }

        private static func writeFolder(_ path: String, to encoder: ArchiveStream) throws {
            let header = ArchiveHeader()
            header.append(.uint(key: Self.type, value: UInt64(ArchiveHeader.EntryType.directory.rawValue)))
            header.append(.string(key: Self.path, value: path))
            header.append(.uint(key: Self.mode, value: 0o755))
            try encoder.writeHeader(header)
        }

        private static func streamFile(
            _ file: BackupArchiveFile,
            from folder: any BackupFileReading,
            to encoder: ArchiveStream,
        ) throws {
            let header = ArchiveHeader()
            header.append(.uint(key: Self.type, value: UInt64(ArchiveHeader.EntryType.regularFile.rawValue)))
            header.append(.string(key: Self.path, value: file.path))
            header.append(.uint(key: Self.mode, value: 0o644))
            header.append(.blob(key: Self.data, size: UInt64(file.byteSize)))
            try encoder.writeHeader(header)
            var written: Int64 = 0
            let found = try folder.stream(file.path) { chunk in
                // Never past the size in the header: a file that grew is damaged, not a longer entry.
                guard written + Int64(chunk.count) <= file.byteSize else {
                    throw BackupError.damaged
                }
                try encoder.writeBlob(key: Self.data, from: chunk)
                written += Int64(chunk.count)
            }
            guard found, written == file.byteSize else {
                throw BackupError.damaged
            }
            if file.byteSize == 0 {
                try Data().withUnsafeBytes { try encoder.writeBlob(key: Self.data, from: $0) }
            }
        }

        private static func writeFile(_ path: String, _ bytes: Data, to encoder: ArchiveStream) throws {
            let header = ArchiveHeader()
            header.append(.uint(key: Self.type, value: UInt64(ArchiveHeader.EntryType.regularFile.rawValue)))
            header.append(.string(key: Self.path, value: path))
            header.append(.uint(key: Self.mode, value: 0o644))
            header.append(.blob(key: Self.data, size: UInt64(bytes.count)))
            try encoder.writeHeader(header)
            try bytes.withUnsafeBytes { buffer in
                try encoder.writeBlob(key: Self.data, from: buffer)
            }
        }

        /// The size of each chunk a streamed file is read in.
        static let chunkSize = 1 << 20

        public func entries(
            of archive: BackupArchiveSource,
            reading: (String) -> BackupArchiveRead,
        ) throws -> [BackupArchiveEntry] {
            switch archive {
            case .data(let data):
                let memory = MemoryByteStream(data)
                guard let stream = ArchiveByteStream.customStream(instance: memory) else {
                    throw BackupError.damaged
                }
                return try Self.entries(of: stream, reading: reading)
            case .file(let url):
                // A file from the picker is only readable inside its security scope, held for this one pass.
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                return try Self.entries(ofFileAt: url, reading: reading)
            }
        }

        /// A picked file, read through `FileReadByteStream`. Any read or I/O error on the way, opening it or
        /// partway through (like iCloud Drive evicting it mid-read), is `unreadableFile`, never `damaged`: only a
        /// file that was read and fails a check is damaged (D207.2). `failingAfter` is for tests.
        static func entries(
            ofFileAt url: URL,
            failingAfter limit: Int? = nil,
            reading: (String) -> BackupArchiveRead,
        ) throws -> [BackupArchiveEntry] {
            let file: FileReadByteStream
            do {
                file = try FileReadByteStream(url, failingAfter: limit)
            } catch {
                throw BackupError.unreadableFile
            }
            guard let stream = ArchiveByteStream.customStream(instance: file) else {
                try? file.close()
                throw BackupError.unreadableFile
            }
            do {
                return try Self.entries(of: stream, reading: reading)
            } catch {
                // The decoder reports a failed read as a bad archive, so the stream's own record decides.
                if file.readFailed {
                    throw BackupError.unreadableFile
                }
                throw error
            }
        }

        private static func entries(
            of stream: ArchiveByteStream,
            reading: (String) -> BackupArchiveRead,
        ) throws -> [BackupArchiveEntry] {
            defer { try? stream.close() }
            guard let decoder = ArchiveStream.decodeStream(readingFrom: stream) else {
                throw BackupError.damaged
            }
            defer { try? decoder.close() }
            var entries: [BackupArchiveEntry] = []
            while true {
                let header: ArchiveHeader?
                do {
                    header = try decoder.readHeader()
                } catch {
                    // Apple Archive refuses to read past an entry with an absolute path or a `..` component. That
                    // entry stands for the rest, so a manifest before it is still read and its version checked
                    // first (L40), and the unsafe-entry check then refuses the archive (L21).
                    guard !entries.isEmpty else {
                        throw BackupError.damaged
                    }
                    entries.append(BackupArchiveEntry(path: "", kind: .other))
                    break
                }
                guard let header else {
                    break
                }
                do {
                    entries.append(try Self.entry(header, decoder, reading))
                } catch let error as BackupError {
                    throw error
                } catch {
                    throw BackupError.damaged
                }
            }
            // An empty archive holds no backup.
            guard !entries.isEmpty else {
                throw BackupError.damaged
            }
            return entries
        }

        private static func entry(
            _ header: ArchiveHeader,
            _ decoder: ArchiveStream,
            _ reading: (String) -> BackupArchiveRead,
        ) throws -> BackupArchiveEntry {
            guard case .string(_, let path) = header.field(forKey: Self.path) else {
                throw BackupError.damaged
            }
            guard case .uint(_, let raw) = header.field(forKey: Self.type) else {
                throw BackupError.damaged
            }
            if isHardLink(header) {
                return BackupArchiveEntry(path: path, kind: .hardLink(target: ""))
            }
            switch ArchiveHeader.EntryType(rawValue: UInt32(raw)) {
            case .directory:
                return BackupArchiveEntry(path: path, kind: .directory)
            case .link:
                var target = ""
                if case .string(_, let value) = header.field(forKey: Self.link) {
                    target = value
                }
                return BackupArchiveEntry(path: path, kind: .symbolicLink(target: target))
            case .regularFile:
                return BackupArchiveEntry(path: path, kind: .file(try fileData(header, decoder, reading(path))))
            default:
                return BackupArchiveEntry(path: path, kind: .other)
            }
        }

        /// A hard link: in a cluster, or with a link count above 1.
        private static func isHardLink(_ header: ArchiveHeader) -> Bool {
            if header.field(forKey: Self.hardLinkCluster) != nil {
                return true
            }
            if case .uint(_, let count) = header.field(forKey: Self.linkCount), count > 1 {
                return true
            }
            return false
        }

        private static func bytes(_ header: ArchiveHeader, _ decoder: ArchiveStream) throws -> Data {
            guard case .blob(_, let size, _) = header.field(forKey: Self.data), size > 0 else {
                return Data()
            }
            var bytes = Data(count: Int(size))
            try bytes.withUnsafeMutableBytes { buffer in
                try decoder.readBlob(key: Self.data, into: buffer)
            }
            return bytes
        }

        /// A regular file's bytes as `read` asks: none, all of them, or streamed and so none kept.
        private static func fileData(
            _ header: ArchiveHeader,
            _ decoder: ArchiveStream,
            _ read: BackupArchiveRead,
        ) throws -> Data? {
            switch read {
            case .skip:
                // A blob that isn't read is skipped by the decoder.
                return nil
            case .data:
                return try bytes(header, decoder)
            case .stream(let body):
                try stream(header, decoder, through: body)
                return nil
            }
        }

        /// The blob read into one reused buffer, `chunkSize` at a time.
        private static func stream(
            _ header: ArchiveHeader,
            _ decoder: ArchiveStream,
            through body: (UnsafeRawBufferPointer) -> Void,
        ) throws {
            guard case .blob(_, let size, _) = header.field(forKey: Self.data), size > 0 else {
                return
            }
            let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: chunkSize, alignment: 1)
            defer { buffer.deallocate() }
            var remaining = Int(size)
            while remaining > 0 {
                let chunk = UnsafeMutableRawBufferPointer(rebasing: buffer[0..<min(remaining, chunkSize)])
                try decoder.readBlob(key: Self.data, into: chunk)
                body(UnsafeRawBufferPointer(chunk))
                remaining -= chunk.count
            }
        }

        /// Every folder a path sits in, parents first.
        static func folders(of paths: [String]) -> [String] {
            var folders = Set<String>()
            for path in paths {
                var parts = path.split(separator: "/").dropLast()
                while !parts.isEmpty {
                    folders.insert(parts.joined(separator: "/"))
                    parts = parts.dropLast()
                }
            }
            return folders.sorted()
        }
    }

    /// An Apple Archive byte stream over `Data` in memory: read from the start, or appended to.
    final class MemoryByteStream: ArchiveByteStreamProtocol {
        private(set) var data: Data
        private var offset = 0

        init(_ data: Data = Data()) {
            self.data = data
        }

        func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
            let count = try read(into: buffer, atOffset: Int64(offset))
            offset += count
            return count
        }

        func read(into buffer: UnsafeMutableRawBufferPointer, atOffset offset: Int64) throws -> Int {
            let start = Int(offset)
            guard start >= 0, start <= data.count else {
                throw CocoaError(.fileReadUnknown)
            }
            let count = min(buffer.count, data.count - start)
            guard count > 0 else {
                return 0
            }
            data.withUnsafeBytes { bytes in
                buffer.copyMemory(from: UnsafeRawBufferPointer(rebasing: bytes[start..<(start + count)]))
            }
            return count
        }

        func write(from buffer: UnsafeRawBufferPointer) throws -> Int {
            let count = try write(from: buffer, atOffset: Int64(offset))
            offset += count
            return count
        }

        func write(from buffer: UnsafeRawBufferPointer, atOffset offset: Int64) throws -> Int {
            let start = Int(offset)
            guard start >= 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
            if data.count < start {
                data.append(Data(count: start - data.count))
            }
            let overlap = min(buffer.count, data.count - start)
            if overlap > 0 {
                data.replaceSubrange(start..<(start + overlap), with: buffer.prefix(overlap))
            }
            if buffer.count > overlap {
                data.append(contentsOf: buffer.suffix(from: overlap))
            }
            return buffer.count
        }

        func seek(toOffset offset: Int64, relativeTo origin: FileDescriptor.SeekOrigin) throws -> Int64 {
            let base: Int =
                switch origin {
                case .start: 0
                case .current: self.offset
                case .end: data.count
                default: throw CocoaError(.fileReadUnknown)
                }
            let target = base + Int(offset)
            guard target >= 0 else {
                throw CocoaError(.fileReadUnknown)
            }
            self.offset = target
            return Int64(target)
        }

        func cancel() {}

        func close() throws {}
    }
#endif
