import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence

/// The ledger's `Attachment`, which Swift Testing's own `Attachment` hides in a test file.
typealias LedgerAttachment = Attachment

/// What was read of the attachments' bytes: every chunk's size, and how often bytes were asked for as one value.
final class AttachmentReadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [Int] = []
    private var whole = 0

    var largestChunk: Int { lock.withLock { chunks.max() ?? 0 } }
    var streamedBytes: Int { lock.withLock { chunks.reduce(0, +) } }
    /// `mappedData(for:)` calls: bytes as one value, which only a restore into the store asks for.
    var wholeReads: Int { lock.withLock { whole } }

    func chunk(_ count: Int) {
        lock.withLock { chunks.append(count) }
    }

    func wholeRead() {
        lock.withLock { whole += 1 }
    }
}

/// Attachment bytes from `base`, logged.
struct LoggedAttachmentBytes: BackupAttachmentReading {
    let base: any BackupAttachmentReading
    let log: AttachmentReadLog

    func stream(_ id: UUID, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
        try base.stream(id) { chunk in
            log.chunk(chunk.count)
            try body(chunk)
        }
    }

    func mappedData(for id: UUID) throws -> Data? {
        log.wholeRead()
        return try base.mappedData(for: id)
    }
}

/// The ledger, as a store that keeps attachments in files would hand it to backups: a backup gets the records
/// without attachment bytes and reads the bytes from `attachmentBytes()`. It records any whole-ledger read or
/// replace, and what a restore hands it (Tech Architect B1).
@MainActor
final class StreamingSpySource: LedgerBackupSource {
    let base: InMemoryLedgerRepository
    /// Reads of the source's attachments for backups.
    let backupReads = AttachmentReadLog()
    /// Reads of the backup's attachments by a restore.
    let restoreReads = AttachmentReadLog()
    private(set) var wholeLedgerReads = 0
    private(set) var wholeLedgerReplaces = 0
    /// For each streamed restore: the size of each attachment's `data` in the snapshot it was handed.
    private(set) var restoredSnapshotBytes: [[Int]] = []
    /// For each streamed restore: whether its bytes came from a backup's files.
    private(set) var restoredFromFiles: [Bool] = []

    init(_ base: InMemoryLedgerRepository) {
        self.base = base
    }

    func ledgerSnapshot() throws -> LedgerSnapshot {
        wholeLedgerReads += 1
        return try base.ledgerSnapshot()
    }

    func replaceLedger(with snapshot: LedgerSnapshot) throws {
        wholeLedgerReplaces += 1
        try base.replaceLedger(with: snapshot)
    }

    func backupSnapshot() throws -> LedgerSnapshot {
        try base.ledgerSnapshot().withoutAttachmentBytes
    }

    func attachmentBytes() throws -> any BackupAttachmentReading {
        let logged = LoggedAttachmentBytes(base: BackupLedgerAttachments(try base.ledgerSnapshot()), log: backupReads)
        return HookedAttachmentBytes(base: logged, hooks: hooks)
    }

    /// What each backup read of an attachment does besides reading it.
    let hooks = StreamHooks()

    func replaceLedger(with snapshot: LedgerSnapshot, attachments: any BackupAttachmentReading) throws {
        restoredSnapshotBytes.append(snapshot.attachments.map(\.data.count))
        restoredFromFiles.append(attachments is BackupFolderAttachments)
        let logged = LoggedAttachmentBytes(base: attachments, log: restoreReads)
        var full = snapshot
        full.attachments = try snapshot.attachments.map { attachment in
            var filled = attachment
            filled.data = try logged.mappedData(for: attachment.id) ?? Data()
            return filled
        }
        try base.replaceLedger(with: full)
    }
}

/// A real folder store that records what goes through it: whole-folder reads, which files a backup is written
/// from in memory, which attachment files are cloned, and each scratch folder for a picked file.
final class StreamingSpyStorage: BackupStorage, @unchecked Sendable {
    let base: FileBackupStorage
    let folder: URL
    private let lock = NSLock()
    private var log = Log()

    struct Log {
        var wholeFolderReads = 0
        var inMemoryWrites = 0
        var writtenInMemory: [[String]] = []
        var unchanged: [Set<String>] = []
        var scratches: [ScratchLog] = []
    }

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-streaming-\(UUID().uuidString)", isDirectory: true)
        base = try FileBackupStorage(folder: folder)
    }

    var recorded: Log { lock.withLock { log } }

    func storedIDs() throws -> [UUID] { try base.storedIDs() }
    func listing(id: UUID) throws -> BackupFolderListing { try base.listing(id: id) }
    func files(id: UUID) throws -> any BackupFileReading { try base.files(id: id) }
    func delete(id: UUID) throws { try base.delete(id: id) }
    func loadStatus() throws -> BackupStatus { try base.loadStatus() }
    func saveStatus(_ status: BackupStatus) throws { try base.saveStatus(status) }

    func read(id: UUID) throws -> BackupSnapshotFiles {
        lock.withLock { log.wholeFolderReads += 1 }
        return try base.read(id: id)
    }

    func write(_ files: BackupSnapshotFiles, id: UUID, cloningFrom earlier: UUID?) throws {
        lock.withLock { log.inMemoryWrites += 1 }
        try base.write(files, id: id, cloningFrom: earlier)
    }

    func write(
        _ files: BackupSnapshotFiles,
        attachments: BackupAttachmentWrites,
        id: UUID,
        cloningFrom earlier: UUID?,
    ) throws {
        lock.withLock {
            log.writtenInMemory.append(files.paths.sorted())
            log.unchanged.append(attachments.unchanged)
        }
        try base.write(files, attachments: attachments, id: id, cloningFrom: earlier)
    }

    func makeExportFolder() throws -> URL { try base.makeExportFolder() }
    func removeExport(_ file: URL) { base.removeExport(file) }

    func makeScratch() throws -> any BackupScratchFolder {
        let scratch = ScratchLog(try base.makeScratch())
        lock.withLock { log.scratches.append(scratch) }
        return scratch
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: folder.path + ".staging"))
    }
}

/// A scratch folder that records each file made in it, the largest chunk written, and whether it was removed.
final class ScratchLog: BackupScratchFolder, @unchecked Sendable {
    private let base: any BackupScratchFolder
    private let lock = NSLock()
    private var paths: [String] = []
    private var largest = 0
    private var removed = false

    init(_ base: any BackupScratchFolder) {
        self.base = base
    }

    var created: [String] { lock.withLock { paths } }
    var largestChunk: Int { lock.withLock { largest } }
    var wasRemoved: Bool { lock.withLock { removed } }

    func create(_ path: String) throws -> any BackupFileWriting {
        lock.withLock { paths.append(path) }
        return Writer(base: try base.create(path), scratch: self)
    }

    func remove() {
        lock.withLock { removed = true }
        base.remove()
    }

    func data(at path: String) throws -> Data? { try base.data(at: path) }

    func stream(_ path: String, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
        try base.stream(path, through: body)
    }

    fileprivate func wrote(_ count: Int) {
        lock.withLock { largest = max(largest, count) }
    }

    private final class Writer: BackupFileWriting {
        let base: any BackupFileWriting
        let scratch: ScratchLog

        init(base: any BackupFileWriting, scratch: ScratchLog) {
            self.base = base
            self.scratch = scratch
        }

        func write(_ bytes: UnsafeRawBufferPointer) throws {
            scratch.wrote(bytes.count)
            try base.write(bytes)
        }

        func close() throws {
            try base.close()
        }
    }
}

/// The fake archive, recording each path whose bytes a pass asked for whole and each it streamed, and streaming in
/// chunks of at most `BackupChunk.size`.
struct RecordingArchiving: BackupArchiving {
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var whole: [String] = []
        private var streamed: [String] = []

        var readWhole: [String] { lock.withLock { whole } }
        var readStreamed: [String] { lock.withLock { streamed } }

        func record(_ path: String, _ read: BackupArchiveRead) {
            lock.withLock {
                switch read {
                case .skip: break
                case .data: whole.append(path)
                case .stream: streamed.append(path)
                }
            }
        }
    }

    let base = FakeBackupArchiving()
    let log = Log()
    let written = WrittenLog()

    func archive(_ files: BackupSnapshotFiles) throws -> Data {
        try base.archive(files)
    }

    /// Records the files in order and each chunk read from `folder`. The fake's own format is then built in
    /// memory, as only the fake does.
    func archive(_ files: [BackupArchiveFile], from folder: any BackupFileReading, to url: URL) throws {
        written.files(files.map(\.path))
        try base.archive(files, from: WrittenLog.Folder(base: folder, log: written), to: url)
    }

    func entries(
        of archive: BackupArchiveSource,
        reading: (String) -> BackupArchiveRead,
    ) throws -> [BackupArchiveEntry] {
        try base.entries(of: archive) { path in
            let read = reading(path)
            log.record(path, read)
            guard case .stream(let body) = read else {
                return read
            }
            // In chunks, the way Apple Archive's reader hands them over.
            return .stream { buffer in
                var offset = 0
                while offset < buffer.count {
                    let end = min(offset + BackupChunk.size, buffer.count)
                    body(UnsafeRawBufferPointer(rebasing: buffer[offset..<end]))
                    offset = end
                }
            }
        }
    }
}

/// Called for every backup read of an attachment, in order from 1, off the main actor: a test can hold a read
/// (`gate`) or change its bytes (`flipped`), as bytes changing between the hash and the write would.
final class StreamHooks: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var flippedCalls: Set<Int> = []
    private var gatedCall: Int?
    private let started = DispatchSemaphore(value: 0)
    private let proceed = DispatchSemaphore(value: 0)
    private var startedFlag = false

    /// The `call`th read has its first byte changed.
    func flip(_ call: Int) {
        lock.withLock { _ = flippedCalls.insert(call) }
    }

    /// The `call`th read waits, before its first chunk, until `release()`.
    func gate(_ call: Int) {
        lock.withLock { gatedCall = call }
    }

    var hasReachedGate: Bool { lock.withLock { startedFlag } }
    var calls: Int { lock.withLock { count } }

    func release() {
        proceed.signal()
    }

    /// Whether this read is flipped. Waits here when it's the gated one.
    fileprivate func next() -> Bool {
        let (gated, flipped) = lock.withLock { () -> (Bool, Bool) in
            count += 1
            return (count == gatedCall, flippedCalls.contains(count))
        }
        if gated {
            lock.withLock { startedFlag = true }
            proceed.wait()
        }
        return flipped
    }
}

struct HookedAttachmentBytes: BackupAttachmentReading {
    let base: any BackupAttachmentReading
    let hooks: StreamHooks

    func stream(_ id: UUID, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
        var flip = hooks.next()
        return try base.stream(id) { chunk in
            guard flip, !chunk.isEmpty else {
                try body(chunk)
                return
            }
            flip = false
            var copy = Data(chunk)
            copy[copy.startIndex] ^= 0xFF
            try copy.withUnsafeBytes { try body($0) }
        }
    }

    func mappedData(for id: UUID) throws -> Data? {
        try base.mappedData(for: id)
    }
}

/// What an export read from the backup folder: the files in archive order, every chunk's size, and any file read
/// whole.
final class WrittenLog: @unchecked Sendable {
    private let lock = NSLock()
    private var order: [[String]] = []
    private var chunks: [Int] = []
    private var whole: [String] = []

    var archived: [[String]] { lock.withLock { order } }
    var largestChunk: Int { lock.withLock { chunks.max() ?? 0 } }
    var readWhole: [String] { lock.withLock { whole } }

    func files(_ paths: [String]) {
        lock.withLock { order.append(paths) }
    }

    struct Folder: BackupFileReading {
        let base: any BackupFileReading
        let log: WrittenLog

        func data(at path: String) throws -> Data? {
            log.lock.withLock { log.whole.append(path) }
            return try base.data(at: path)
        }

        func stream(_ path: String, through body: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
            try base.stream(path) { chunk in
                log.lock.withLock { log.chunks.append(chunk.count) }
                try body(chunk)
            }
        }
    }
}
