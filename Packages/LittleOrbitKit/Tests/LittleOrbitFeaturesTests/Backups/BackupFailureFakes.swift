import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence

/// A real folder store with switchable failures: a full disk on writes and export staging, read errors, folders
/// that can't be removed, a status that can't be read once a write has found the disk full, and backup folders
/// that can't be read at all (D214), with the creation date each one reports.
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
        statusErrorAfterFullDisk: (any Error)?.none,
        statusError: (any Error)?.none,
        statusSaves: 0,
        unreadable: [UUID: Date?](),
        deletes: 0,
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

    /// Set as the status's read error when a write finds the disk full.
    var statusErrorAfterFullDisk: (any Error)? {
        get { lock.withLock { state.statusErrorAfterFullDisk } }
        set { lock.withLock { state.statusErrorAfterFullDisk = newValue } }
    }
    var statusSaves: Int { lock.withLock { state.statusSaves } }

    private func fullDisk() -> BackupError {
        lock.withLock { state.statusError = state.statusErrorAfterFullDisk }
        return .notEnoughStorage
    }

    /// Folders that can't be read at all, as a folder at mode 000: listing and reading them throws a read
    /// failure. The value is the creation date the folder reports, `nil` for none.
    var unreadable: [UUID: Date?] {
        get { lock.withLock { state.unreadable } }
        set { lock.withLock { state.unreadable = newValue } }
    }
    var deletes: Int { lock.withLock { state.deletes } }

    private func checkReadable(_ id: UUID) throws {
        if lock.withLock({ state.unreadable[id] != nil }) {
            throw BackupFileReadError(CocoaError(.fileReadNoPermission))
        }
    }

    func folderCreationDate(id: UUID) -> Date? {
        if let scripted = lock.withLock({ state.unreadable[id] }) {
            return scripted
        }
        return base.folderCreationDate(id: id)
    }

    func storedIDs() throws -> [UUID] {
        if let listError { throw listError }
        return try base.storedIDs()
    }
    func listing(id: UUID) throws -> BackupFolderListing {
        try checkReadable(id)
        return try base.listing(id: id)
    }
    func read(id: UUID) throws -> BackupSnapshotFiles {
        try checkReadable(id)
        if let readError { throw readError }
        return try base.read(id: id)
    }
    func files(id: UUID) throws -> any BackupFileReading {
        try checkReadable(id)
        if let readError { throw readError }
        return try base.files(id: id)
    }
    func delete(id: UUID) throws {
        if let deleteError { throw deleteError }
        try base.delete(id: id)
        lock.withLock {
            state.deletes += 1
            state.unreadable[id] = nil
        }
    }
    func loadStatus() throws -> BackupStatus {
        if let error = lock.withLock({ state.statusError }) { throw error }
        return try base.loadStatus()
    }
    func saveStatus(_ status: BackupStatus) throws {
        lock.withLock { state.statusSaves += 1 }
        try base.saveStatus(status)
    }
    func makeScratch() throws -> any BackupScratchFolder { try base.makeScratch() }
    func makeExportFolder() throws -> URL {
        if let exportFolderError { throw exportFolderError }
        return try base.makeExportFolder()
    }
    func removeExport(_ file: URL) { base.removeExport(file) }

    func write(_ files: BackupSnapshotFiles, id: UUID, cloningFrom earlier: UUID?) throws {
        if diskFull { throw fullDisk() }
        if let writeError { throw writeError }
        try base.write(files, id: id, cloningFrom: earlier)
    }

    func write(
        _ files: BackupSnapshotFiles,
        attachments: BackupAttachmentWrites,
        id: UUID,
        cloningFrom earlier: UUID?,
    ) throws {
        if diskFull { throw fullDisk() }
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
