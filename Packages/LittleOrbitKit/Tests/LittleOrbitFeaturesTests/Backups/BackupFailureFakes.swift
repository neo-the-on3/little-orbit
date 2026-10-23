import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence

/// A real folder store with switchable failures: a full disk on writes and export staging, read errors, and
/// folders that can't be removed.
final class ScriptedStorage: BackupStorage, @unchecked Sendable {
    let base: FileBackupStorage
    private let lock = NSLock()
    private var state = (
        diskFull: false,
        exportFolderError: (any Error)?.none,
        readError: (any Error)?.none,
        deleteError: (any Error)?.none,
        writeError: (any Error)?.none,
        listError: (any Error)?.none,
    )

    init(folder: URL) throws {
        base = try FileBackupStorage(folder: folder)
    }

    var diskFull: Bool {
        get { lock.withLock { state.diskFull } }
        set { lock.withLock { state.diskFull = newValue } }
    }
    var exportFolderError: (any Error)? {
        get { lock.withLock { state.exportFolderError } }
        set { lock.withLock { state.exportFolderError = newValue } }
    }
    var readError: (any Error)? {
        get { lock.withLock { state.readError } }
        set { lock.withLock { state.readError = newValue } }
    }
    var deleteError: (any Error)? {
        get { lock.withLock { state.deleteError } }
        set { lock.withLock { state.deleteError = newValue } }
    }

    var writeError: (any Error)? {
        get { lock.withLock { state.writeError } }
        set { lock.withLock { state.writeError = newValue } }
    }
    var listError: (any Error)? {
        get { lock.withLock { state.listError } }
        set { lock.withLock { state.listError = newValue } }
    }

    func storedIDs() throws -> [UUID] {
        if let listError { throw listError }
        return try base.storedIDs()
    }
    func listing(id: UUID) throws -> BackupFolderListing { try base.listing(id: id) }
    func read(id: UUID) throws -> BackupSnapshotFiles {
        if let readError { throw readError }
        return try base.read(id: id)
    }
    func files(id: UUID) throws -> any BackupFileReading {
        if let readError { throw readError }
        return try base.files(id: id)
    }
    func delete(id: UUID) throws {
        if let deleteError { throw deleteError }
        try base.delete(id: id)
    }
    func loadStatus() throws -> BackupStatus { try base.loadStatus() }
    func saveStatus(_ status: BackupStatus) throws { try base.saveStatus(status) }
    func makeScratch() throws -> any BackupScratchFolder { try base.makeScratch() }
    func makeExportFolder() throws -> URL {
        if let exportFolderError { throw exportFolderError }
        return try base.makeExportFolder()
    }
    func removeExport(_ file: URL) { base.removeExport(file) }

    func write(_ files: BackupSnapshotFiles, id: UUID, cloningFrom earlier: UUID?) throws {
        if diskFull { throw BackupError.notEnoughStorage }
        if let writeError { throw writeError }
        try base.write(files, id: id, cloningFrom: earlier)
    }

    func write(
        _ files: BackupSnapshotFiles,
        attachments: BackupAttachmentWrites,
        id: UUID,
        cloningFrom earlier: UUID?,
    ) throws {
        if diskFull { throw BackupError.notEnoughStorage }
        if let writeError { throw writeError }
        try base.write(files, attachments: attachments, id: id, cloningFrom: earlier)
    }
}

/// The fake archive, whose export file can't be written.
struct FailingExportArchiving: BackupArchiving {
    let failure: any Error & Sendable
    private let base = FakeBackupArchiving()

    func archive(_ files: BackupSnapshotFiles) throws -> Data { try base.archive(files) }
    func entries(
        of archive: BackupArchiveSource,
        reading: (String) -> BackupArchiveRead,
    ) throws -> [BackupArchiveEntry] {
        try base.entries(of: archive, reading: reading)
    }

    func archive(_ files: [BackupArchiveFile], from folder: any BackupFileReading, to url: URL) throws {
        throw failure
    }
}
