import Foundation
import LittleOrbitDomain

#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

/// Attachment files written and read in chunks, never held whole (Tech Architect B1).
extension FileBackupStorage {
    /// A scratch folder in the staging folder, `<uuid>.restore`, for a picked file's attachments. The launch sweep
    /// removes one an interrupted restore left (D197.4).
    public func makeScratch() throws -> any BackupScratchFolder {
        let url = stagingURL.appendingPathComponent("\(UUID().uuidString).restore", isDirectory: true)
        try prepare(stagingURL)
        try prepare(url)
        return FileScratchFolder(url, prepare: { [self] in try prepare($0) })
    }

    /// A new file at `url`, filled by `produce` one chunk at a time, with the default data protection class on iOS.
    static func streamFile(
        to url: URL,
        _ produce: ((UnsafeRawBufferPointer) throws -> Void) throws -> Void,
    ) throws {
        let writer = try FileChunkWriter(url)
        do {
            try produce { try writer.write($0) }
            try writer.close()
        } catch {
            try? writer.close()
            throw error
        }
    }

    static func isRegularFile(_ url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.type] as? FileAttributeType == .typeRegular
    }
}

/// One file read in order into a single reused buffer, chunk by chunk. `FileHandle.read(upToCount:)` would hand
/// back a new `Data` for each chunk, and those can stay in an autorelease pool until the whole backup is done.
enum FileChunkReader {
    static func stream(
        _ url: URL,
        chunkSize: Int,
        through body: (UnsafeRawBufferPointer) throws -> Void,
    ) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: chunkSize, alignment: 16)
        defer { buffer.deallocate() }
        guard let base = buffer.baseAddress else {
            return
        }
        while true {
            let count = read(handle.fileDescriptor, base, chunkSize)
            if count < 0 {
                guard errno == EINTR else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                continue
            }
            if count == 0 {
                return
            }
            try body(UnsafeRawBufferPointer(rebasing: buffer[0..<count]))
        }
    }

    private static func read(_ descriptor: Int32, _ bytes: UnsafeMutableRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
            Darwin.read(descriptor, bytes, count)
        #else
            Glibc.read(descriptor, bytes, count)
        #endif
    }
}

/// One new file, written in order, chunk by chunk.
final class FileChunkWriter: BackupFileWriting {
    private let handle: FileHandle
    private var closed = false

    init(_ url: URL) throws {
        #if os(iOS) || os(watchOS)
            let attributes: [FileAttributeKey: Any]? = [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
        #else
            let attributes: [FileAttributeKey: Any]? = nil
        #endif
        guard !FileManager.default.fileExists(atPath: url.path),
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: attributes)
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
    }

    func write(_ bytes: UnsafeRawBufferPointer) throws {
        guard let base = bytes.baseAddress, !bytes.isEmpty else {
            return
        }
        // Straight to the descriptor: `FileHandle.write(contentsOf:)` wants a `Data` copy of each chunk, which can
        // stay in an autorelease pool until the whole backup is done.
        var offset = 0
        while offset < bytes.count {
            let written = Self.write(handle.fileDescriptor, base + offset, bytes.count - offset)
            if written < 0 {
                guard errno == EINTR else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                continue
            }
            offset += written
        }
    }

    private static func write(_ descriptor: Int32, _ bytes: UnsafeRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
            Darwin.write(descriptor, bytes, count)
        #else
            Glibc.write(descriptor, bytes, count)
        #endif
    }

    func close() throws {
        guard !closed else {
            return
        }
        closed = true
        try handle.close()
    }
}

/// A picked file's attachments, unpacked after every check passes and read back a file at a time (B1).
final class FileScratchFolder: BackupScratchFolder, @unchecked Sendable {
    private let url: URL
    private let prepare: (URL) throws -> Void
    private let reading: StoredBackupFolder

    init(_ url: URL, prepare: @escaping (URL) throws -> Void) {
        self.url = url
        self.prepare = prepare
        reading = StoredBackupFolder(url)
    }

    func create(_ path: String) throws -> any BackupFileWriting {
        guard BackupFormat.isContained(path) else {
            throw BackupError.damaged
        }
        let file = url.appendingPathComponent(path)
        try prepare(file.deletingLastPathComponent())
        return try FileChunkWriter(file)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    func data(at path: String) throws -> Data? {
        try reading.data(at: path)
    }

    func stream(_ path: String, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
        try reading.stream(path, through: body)
    }
}
