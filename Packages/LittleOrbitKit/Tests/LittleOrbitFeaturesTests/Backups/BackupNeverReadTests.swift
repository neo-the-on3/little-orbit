import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// D202.1 (L48, L49): a damaged folder that was never listed with a readable manifest. Its date is the folder's,
/// its size the total of its files, and "Unknown" stands in for either when it can't be read.
@MainActor
@Suite("Backup list: a damaged folder that was never read", .timeLimit(.minutes(2)))
struct BackupNeverReadTests {
    private let presentation = BackupPresentation(
        locale: Locale(identifier: "en_US"),
        timeZone: TimeZone(identifier: "Asia/Kolkata") ?? .gmt,
        device: .iPhone,
    )

    /// A folder with two files and no manifest, made by hand so the list has never seen it.
    private func strayFolder(in folder: URL, sizes: [Int] = [1_500, 900]) throws -> UUID {
        let id = UUID()
        let url = folder.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (index, size) in sizes.enumerated() {
            try Data(repeating: 1, count: size).write(to: url.appendingPathComponent("file\(index).json"))
        }
        return id
    }

    @Test("Its date is the folder's, its size the total of its files, and it sorts by that date (L48)")
    func folderDateAndSize() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-tests-\(UUID().uuidString)", isDirectory: true)
        let storage = try ListingOverrideStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        let backup = try await harness.service.backUpNow()
        let stray = try strayFolder(in: folder)
        storage.createdAt[stray] = harness.now.addingTimeInterval(-86_400)

        let backups = try await harness.service.overview().backups
        #expect(backups.map(\.id) == [backup.id, stray])
        let record = try #require(backups.last)
        #expect(record.condition == .damaged)
        #expect(record.kind == nil)
        #expect(record.byteSize == 2_400)
        #expect(record.createdAt == harness.now.addingTimeInterval(-86_400))
        let row = presentation.row(record, now: harness.now)
        #expect(row.title == presentation.date(record.createdAt, now: harness.now))
        #expect(row.sizeText == presentation.size(2_400))
        #expect(row.sizeText != presentation.size(0))
        #expect(row.kindText == "Unknown")
        #expect(row.formatText == "Format unknown")
        #expect(row.statusText == "Damaged")
    }

    @Test("A size or date that can't be read shows Unknown, never Zero KB or a year-1 date, and sorts last (L49)")
    func nothingReadable() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-tests-\(UUID().uuidString)", isDirectory: true)
        let storage = try ListingOverrideStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        let backup = try await harness.service.backUpNow()
        let dated = try strayFolder(in: folder)
        storage.createdAt[dated] = harness.now.addingTimeInterval(-86_400 * 400)
        let blank = try strayFolder(in: folder)
        storage.createdAt[blank] = .some(nil)
        storage.sizesUnknown.insert(blank)
        let empty = try strayFolder(in: folder, sizes: [])
        storage.createdAt[empty] = harness.now.addingTimeInterval(-3_600)

        let backups = try await harness.service.overview().backups
        #expect(backups.map(\.id) == [backup.id, empty, dated, blank])
        let record = try #require(backups.last)
        #expect(record.byteSize == nil)
        #expect(!record.isDateKnown)
        let row = presentation.row(record, now: harness.now)
        #expect(row.title == "Unknown")
        #expect(row.sizeText == "Unknown")
        #expect(!row.title.contains("1"))
        #expect(row.accessibilityLabel.hasPrefix("Unknown, Unknown backup, Damaged, Unknown"))
        // Zero KB only for a folder that really is empty.
        let emptyRow = presentation.row(backups[1], now: harness.now)
        #expect(backups[1].byteSize == 0)
        #expect(emptyRow.sizeText == presentation.size(0))
    }

    @Test("After a relaunch, a folder that lost its manifest follows the never-seen rule (D202, D210)")
    func manifestLostAcrossRelaunch() async throws {
        let first = try BackupHarness()
        let backup = try await first.service.backUpNow()
        _ = try await first.service.overview()
        let url = first.backupFolder(backup.id)
        try FileManager.default.removeItem(at: url.appendingPathComponent(BackupFormat.manifestPath))
        let remaining = try FileManager.default.subpathsOfDirectory(atPath: url.path)
            .reduce(Int64(0)) { total, path in
                let attributes = try FileManager.default.attributesOfItem(atPath: url.appendingPathComponent(path).path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    return total
                }
                return total + ((attributes[.size] as? NSNumber)?.int64Value ?? 0)
            }
        let folderCreated = try FileManager.default.attributesOfItem(atPath: url.path)[.creationDate] as? Date

        // A relaunch: a new store over the same folders, with only what's on disk to go on.
        let relaunched = try BackupHarness(storage: FileBackupStorage(folder: first.folder))
        let backups = try await relaunched.service.overview().backups
        let record = try #require(backups.first)
        #expect(backups.count == 1)
        #expect(record.condition == .damaged)
        #expect(!record.isRestorable)
        #expect(record.byteSize == remaining)
        #expect(record.byteSize != 0)
        let row = presentation.row(record, now: relaunched.now)
        #expect(row.kindText == "Unknown")
        #expect(row.statusText == "Damaged")
        #expect(row.sizeText == presentation.size(remaining))
        if let folderCreated {
            #expect(record.createdAt == folderCreated)
            #expect(row.title == presentation.date(folderCreated, now: relaunched.now))
        } else {
            // A platform that doesn't report a folder's creation date: "Unknown", never a made-up date (L49).
            #expect(row.title == "Unknown")
        }
        #expect(row.detailAccountsText == "Unknown")
        #expect(row.detailTransactionsText == "Unknown")
        #expect(!row.canRestore)
        // Export… stays unavailable (D196.3); Delete still works.
        await #expect(throws: BackupError.damaged) {
            try await relaunched.service.exportBackup(id: record.id, named: "a.littleorbit-backup")
        }
        try await relaunched.service.deleteBackup(id: record.id)
        #expect(try await relaunched.service.overview().backups.isEmpty)
    }
}

/// The real folder store, with a folder's creation date set by the test (an unset date where `nil`) and its file
/// sizes marked unreadable, as when `attributesOfItem` fails.
final class ListingOverrideStorage: BackupStorage, @unchecked Sendable {
    let base: FileBackupStorage
    private let lock = NSLock()
    private var dates: [UUID: Date?] = [:]
    private var unsized: Set<UUID> = []

    init(folder: URL) throws {
        base = try FileBackupStorage(folder: folder)
    }

    var createdAt: [UUID: Date?] {
        get { lock.withLock { dates } }
        set { lock.withLock { dates = newValue } }
    }

    var sizesUnknown: Set<UUID> {
        get { lock.withLock { unsized } }
        set { lock.withLock { unsized = newValue } }
    }

    func listing(id: UUID) throws -> BackupFolderListing {
        var listing = try base.listing(id: id)
        if let date = createdAt[id] {
            listing.createdAt = date
        }
        if sizesUnknown.contains(id) {
            listing.sizesKnown = false
            listing.fileSizes = [:]
        }
        return listing
    }

    func read(id: UUID) throws -> BackupSnapshotFiles { try base.read(id: id) }
    func delete(id: UUID) throws { try base.delete(id: id) }
    func storedIDs() throws -> [UUID] { try base.storedIDs() }
    func loadStatus() throws -> BackupStatus { try base.loadStatus() }
    func saveStatus(_ status: BackupStatus) throws { try base.saveStatus(status) }
    func write(_ files: BackupSnapshotFiles, id: UUID, cloningFrom earlier: UUID?) throws {
        try base.write(files, id: id, cloningFrom: earlier)
    }
}
