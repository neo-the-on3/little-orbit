import Foundation

/// Attachment bytes by attachment ID, handed over one attachment at a time, so a backup, a restore or an import
/// never holds every attachment at once (Tech Architect B1). Safe to use off the main actor.
public protocol BackupAttachmentReading: Sendable {
    /// Hands attachment `id`'s bytes to `body` in chunks, in order. `false` when there are none.
    func stream(_ id: UUID, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool
    /// The bytes as one value, only for a store that takes nothing else (SwiftData's external storage). Where the
    /// bytes are in a file, the value is memory-mapped from that file, not read into memory. `nil` when there are
    /// none.
    func mappedData(for id: UUID) throws -> Data?
}

/// The size of each chunk attachment bytes are streamed in.
public enum BackupChunk {
    public static let size = 1 << 20
}

/// Attachment bytes already in memory, as an in-memory ledger holds them.
public struct BackupLedgerAttachments: BackupAttachmentReading {
    private let bytes: [UUID: Data]

    public init(_ ledger: LedgerSnapshot) {
        bytes = Dictionary(ledger.attachments.map { ($0.id, $0.data) }, uniquingKeysWith: { first, _ in first })
    }

    public func stream(_ id: UUID, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
        guard let data = bytes[id] else {
            return false
        }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            repeat {
                let end = min(offset + BackupChunk.size, buffer.count)
                try body(UnsafeRawBufferPointer(rebasing: buffer[offset..<end]))
                offset = end
            } while offset < buffer.count
        }
        return true
    }

    public func mappedData(for id: UUID) throws -> Data? {
        bytes[id]
    }
}

/// Attachment bytes in a backup folder's `attachments/<id>` files: a stored backup, or a picked file's attachments
/// unpacked after every check passed (B1).
public struct BackupFolderAttachments: BackupAttachmentReading {
    private let folder: any BackupFileReading

    public init(_ folder: any BackupFileReading) {
        self.folder = folder
    }

    public func stream(_ id: UUID, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
        try folder.stream(BackupCodec.attachmentPath(id), through: body)
    }

    public func mappedData(for id: UUID) throws -> Data? {
        try folder.data(at: BackupCodec.attachmentPath(id))
    }
}

/// A backup folder's contents, checked, with each attachment's details but not its bytes (`data` is empty), and
/// where to read the bytes, one attachment at a time (B1).
public struct BackupOpened: Sendable {
    public var contents: BackupContents
    public var attachments: any BackupAttachmentReading

    public init(contents: BackupContents, attachments: any BackupAttachmentReading) {
        self.contents = contents
        self.attachments = attachments
    }
}

/// The attachment files a new backup folder gets besides its JSON files (B1, D195.1).
public struct BackupAttachmentWrites: Sendable {
    /// Every attachment file by path, with the attachment whose bytes it holds.
    public var ids: [String: UUID]
    /// Paths whose file in the earlier backup has the same size and SHA-256 by its manifest: cloned from it
    /// instead of written again. A store that can't clone writes them from `bytes`.
    public var unchanged: Set<String>
    public var bytes: any BackupAttachmentReading

    public init(ids: [String: UUID] = [:], unchanged: Set<String> = [], bytes: any BackupAttachmentReading) {
        self.ids = ids
        self.unchanged = unchanged
        self.bytes = bytes
    }

    /// Every attachment read whole, for a store that writes only from memory.
    func files() throws -> BackupSnapshotFiles {
        var files = BackupSnapshotFiles()
        for (path, id) in ids {
            var data = Data()
            _ = try bytes.stream(id) { data.append(contentsOf: $0) }
            files[path] = data
        }
        return files
    }
}

/// A folder in the app's own container for a picked file's attachments. They're unpacked into it only after every
/// import check passes (D197a.1), so the restore can hand each one to the store from a file (B1). Removed when the
/// restore ends; anything left by an interrupted one goes at the next launch.
public protocol BackupScratchFolder: BackupFileReading {
    /// A new file at `path`, written in order.
    func create(_ path: String) throws -> any BackupFileWriting
    /// Removes the folder and everything in it.
    func remove()
}

/// One file being written in chunks.
public protocol BackupFileWriting: AnyObject {
    func write(_ bytes: UnsafeRawBufferPointer) throws
    func close() throws
}

/// A scratch folder in memory, for stores with no folder of their own.
public final class BackupMemoryScratch: BackupScratchFolder, @unchecked Sendable {
    private let lock = NSLock()
    private var files = BackupSnapshotFiles()

    public init() {}

    public func create(_ path: String) throws -> any BackupFileWriting {
        Writer { [weak self] data in
            guard let self else {
                return
            }
            lock.withLock { files[path] = data }
        }
    }

    public func remove() {
        lock.withLock { files = BackupSnapshotFiles() }
    }

    public func data(at path: String) throws -> Data? {
        lock.withLock { files[path] }
    }

    public func stream(_ path: String, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
        try lock.withLock { files }.stream(path, through: body)
    }

    private final class Writer: BackupFileWriting {
        private var data = Data()
        private let done: (Data) -> Void

        init(_ done: @escaping (Data) -> Void) {
            self.done = done
        }

        func write(_ bytes: UnsafeRawBufferPointer) throws {
            data.append(contentsOf: bytes)
        }

        func close() throws {
            done(data)
        }
    }
}

extension LedgerSnapshot {
    /// The same records, each attachment without its bytes: `data` is empty and `byteSize` stays.
    public var withoutAttachmentBytes: LedgerSnapshot {
        var snapshot = self
        snapshot.attachments = attachments.map { attachment in
            var details = attachment
            details.data = Data()
            return details
        }
        return snapshot
    }
}
