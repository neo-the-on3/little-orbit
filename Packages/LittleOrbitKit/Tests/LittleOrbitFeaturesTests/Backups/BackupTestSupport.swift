import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// A backup service over an in-memory ledger and a real folder store in a temporary folder, with a settable clock,
/// in-memory settings and the fake archive.
@MainActor
final class BackupHarness {
    let repository: InMemoryLedgerRepository
    let folder: URL
    let storage: any BackupStorage
    let clock = BackupClock()
    let zone: TimeZone
    private let zones: BackupZones
    let changes = LedgerChanges()
    let settings = MemoryBackupSettings()
    let archiving: any BackupArchiving
    let hashing: any BackupHashing
    let service: BackupService

    /// 2026-10-22 09:12:05 IST.
    static let morning = Date(timeIntervalSince1970: 1_792_640_525)

    /// `source` defaults to `repository`; tests pass a failing wrapper. `archiving` defaults to the fake archive.
    init(
        repository: InMemoryLedgerRepository? = nil,
        storage: (any BackupStorage)? = nil,
        archiving: (any BackupArchiving)? = nil,
        hashing: (any BackupHashing)? = nil,
        source: ((InMemoryLedgerRepository) -> any LedgerBackupSource)? = nil,
        zone: TimeZone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt,
    ) throws {
        self.zone = zone
        self.archiving = archiving ?? FakeBackupArchiving()
        let hashing = hashing ?? FakeBackupHashing()
        self.hashing = hashing
        let repository = try repository ?? FeatureFixture.repository()
        self.repository = repository
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-tests-\(UUID().uuidString)", isDirectory: true)
        let zones = BackupZones(zone)
        self.zones = zones
        self.storage = try storage ?? FileBackupStorage(folder: folder, timeZone: { zones.current })
        let clock = clock
        service = BackupService(
            source: source?(repository) ?? repository,
            storage: self.storage,
            archiving: self.archiving,
            settings: settings,
            hashing: hashing,
            changes: changes,
            schemaVersion: "1.0.0",
            now: { clock.now },
            timeZone: { zones.current },
        )
    }

    /// The device's time zone changes, as when travelling; backups made from now on use it.
    func move(to zone: TimeZone) {
        zones.current = zone
    }

    var now: Date {
        clock.now
    }

    /// A backup's whole contents, checked first the way a restore is, so a failed check is remembered. The app has
    /// no such call: a restore hands attachments to the store one at a time (B1).
    func contents(_ source: BackupSource) async throws -> BackupContents {
        _ = try await service.checkBackup(source)
        let codec = BackupCodec(hashing: hashing)
        switch source {
        case .stored(let id):
            return try codec.decode(reading: storage.files(id: id))
        case .archive(let archive):
            return try BackupArchiveImport(archiving: archiving, codec: codec).contents(of: archive)
        }
    }

    /// An export's bytes, read from its file, which is then removed as the panel would.
    func exportData(_ id: UUID) async throws -> Data {
        let export = try await service.exportBackup(id: id)
        defer { service.discardExport(export) }
        return try Data(contentsOf: export.file)
    }

    func advance(_ seconds: TimeInterval) {
        clock.now += seconds
    }

    /// The backup folders, by name: every folder in the Backups folder (D209).
    func storedFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { name in
                var isDirectory: ObjCBool = false
                return !name.hasPrefix(".")
                    && FileManager.default.fileExists(
                        atPath: folder.appendingPathComponent(name).path,
                        isDirectory: &isDirectory,
                    ) && isDirectory.boolValue
            }
            .sorted()
    }

    /// The backup's folder, by its date-and-time name (D209), or by its ID for one a test made by hand.
    func backupFolder(_ id: UUID) -> URL {
        (storage as? FileBackupStorage)?.folderURL(id)
            ?? folder.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func viewModel(
        authentication: any AppAuthenticationUseCase = AppLockOff(),
        announce: @escaping @MainActor (String) -> Void = { _ in },
    ) -> BackupsViewModel {
        BackupsViewModel(
            useCases: BackupUseCases(service: service, authentication: authentication),
            presentation: BackupPresentation(
                locale: Locale(identifier: "en_US"),
                timeZone: zone,
                device: .iPhone,
            ),
            now: { [clock] in clock.now },
            announce: announce,
        )
    }

    /// One window's Backups state over a new view model.
    func window(
        authentication: any AppAuthenticationUseCase = AppLockOff(),
        announce: @escaping @MainActor (String) -> Void = { _ in },
    ) -> BackupsWindow {
        BackupsWindow(model: viewModel(authentication: authentication, announce: announce))
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: folder.path + ".staging"))
    }
}

/// The device's current time zone, read off the main actor too.
final class BackupZones: @unchecked Sendable {
    private let lock = NSLock()
    private var zone: TimeZone

    init(_ zone: TimeZone) {
        self.zone = zone
    }

    var current: TimeZone {
        get { lock.withLock { zone } }
        set { lock.withLock { zone = newValue } }
    }
}

@MainActor
final class BackupClock {
    var now = BackupHarness.morning
}

/// A disk that's full: every write fails without leaving a folder.
final class FullDiskStorage: BackupStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var status = BackupStatus()

    func storedIDs() throws -> [UUID] { [] }
    func listing(id: UUID) throws -> BackupFolderListing { throw BackupError.notFound }
    func read(id: UUID) throws -> BackupSnapshotFiles { throw BackupError.notFound }
    func delete(id: UUID) throws {}
    func loadStatus() throws -> BackupStatus { lock.withLock { status } }
    func saveStatus(_ status: BackupStatus) throws { lock.withLock { self.status = status } }

    func write(_ files: BackupSnapshotFiles, id: UUID, cloningFrom earlier: UUID?) throws {
        throw BackupError.notEnoughStorage
    }
}

/// N and M in memory, as `UserDefaultsBackupSettings` keeps them.
final class MemoryBackupSettings: BackupSettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value = BackupRetention.default

    func retention() -> BackupRetention { lock.withLock { value } }
    func setRetention(_ retention: BackupRetention) { lock.withLock { value = retention } }
}

/// A stand-in for Apple Archive so export and restore from a file run on Linux: the entries as JSON. `crafted`
/// builds archives with any entry, links and unsafe paths included.
struct FakeBackupArchiving: BackupArchiving {
    private struct Stored: Codable {
        var path: String
        var kind: String
        var data: Data?
        var target: String?
    }

    func archive(_ files: BackupSnapshotFiles) throws -> Data {
        try Self.crafted(files.paths.map { BackupArchiveEntry(path: $0, kind: .file(files[$0] ?? Data())) })
    }

    func entries(
        of archive: BackupArchiveSource,
        reading: (String) -> BackupArchiveRead,
    ) throws -> [BackupArchiveEntry] {
        let data: Data =
            switch archive {
            case .data(let data): data
            // A file that can't be read at all is `unreadableFile`, the way Apple Archive's reader does (D207.2).
            case .file(let url): try Self.read(url)
            }
        guard let stored = try? JSONDecoder().decode([Stored].self, from: data) else {
            throw BackupError.damaged
        }
        return stored.map { entry in
            let kind: BackupArchiveEntry.Kind =
                switch entry.kind {
                case "file": .file(Self.read(entry.data ?? Data(), reading(entry.path)))
                case "directory": .directory
                case "symlink": .symbolicLink(target: entry.target ?? "")
                case "hardlink": .hardLink(target: entry.target ?? "")
                default: .other
                }
            return BackupArchiveEntry(path: entry.path, kind: kind)
        }
    }

    private static func read(_ data: Data, _ mode: BackupArchiveRead) -> Data? {
        switch mode {
        case .skip:
            return nil
        case .data:
            return data
        case .stream(let body):
            data.withUnsafeBytes { body($0) }
            return nil
        }
    }

    static func read(_ url: URL) throws -> Data {
        guard let data = try? Data(contentsOf: url) else {
            throw BackupError.unreadableFile
        }
        return data
    }

    static func crafted(_ entries: [BackupArchiveEntry]) throws -> Data {
        let stored = entries.map { entry in
            switch entry.kind {
            case .file(let data): Stored(path: entry.path, kind: "file", data: data)
            case .directory: Stored(path: entry.path, kind: "directory")
            case .symbolicLink(let target): Stored(path: entry.path, kind: "symlink", target: target)
            case .hardLink(let target): Stored(path: entry.path, kind: "hardlink", target: target)
            case .other: Stored(path: entry.path, kind: "other")
            }
        }
        return try JSONEncoder().encode(stored)
    }
}

/// App Lock that's on: it records each prompt and answers with `allows`.
@MainActor
final class RecordingAuthentication: AppAuthenticationUseCase {
    var allows: Bool
    private(set) var purposes: [AppAuthenticationPurpose] = []

    init(allows: Bool) {
        self.allows = allows
    }

    func authenticate(for purpose: AppAuthenticationPurpose) async -> Bool {
        purposes.append(purpose)
        return allows
    }

    func unlockMethod() -> AppUnlockMethod {
        .faceID
    }
}

/// Newer ICU puts a narrow no-break space before AM and PM; the tests compare with plain spaces.
func spaced(_ text: String?) -> String {
    (text ?? "").replacingOccurrences(of: "\u{202F}", with: " ")
}

/// A real folder store whose disk can fill up between writes.
final class FillingDiskStorage: BackupStorage, @unchecked Sendable {
    private let base: FileBackupStorage
    private let lock = NSLock()
    private var full = false

    init(folder: URL) throws {
        base = try FileBackupStorage(folder: folder)
    }

    func fill() {
        lock.withLock { full = true }
    }

    func storedIDs() throws -> [UUID] { try base.storedIDs() }
    func listing(id: UUID) throws -> BackupFolderListing { try base.listing(id: id) }
    func read(id: UUID) throws -> BackupSnapshotFiles { try base.read(id: id) }
    func delete(id: UUID) throws { try base.delete(id: id) }
    func loadStatus() throws -> BackupStatus { try base.loadStatus() }
    func saveStatus(_ status: BackupStatus) throws { try base.saveStatus(status) }

    func write(_ files: BackupSnapshotFiles, id: UUID, cloningFrom earlier: UUID?) throws {
        if lock.withLock({ full }) {
            throw BackupError.notEnoughStorage
        }
        try base.write(files, id: id, cloningFrom: earlier)
    }
}

/// A ledger whose replace fails, as a failed SwiftData save would: nothing changes.
@MainActor
final class FailingReplaceSource: LedgerBackupSource {
    private let base: InMemoryLedgerRepository
    private let error: any Error

    init(_ base: InMemoryLedgerRepository, error: any Error = CocoaError(.fileWriteUnknown)) {
        self.base = base
        self.error = error
    }

    func ledgerSnapshot() throws -> LedgerSnapshot {
        try base.ledgerSnapshot()
    }

    func replaceLedger(with snapshot: LedgerSnapshot) throws {
        throw error
    }
}

/// A real folder store whose folders can't be read, as when a protected file is read while the device is locked
/// (R3). Records every delete.
final class LockedFilesStorage: BackupStorage, @unchecked Sendable {
    let base: FileBackupStorage
    private let lock = NSLock()
    private var readsFail = false
    private(set) var deletes = 0
    /// What a read throws while the files are locked.
    private let failure: any Error

    init(folder: URL, failure: any Error = CocoaError(.fileReadNoPermission)) throws {
        base = try FileBackupStorage(folder: folder)
        self.failure = failure
    }

    func lockFiles() {
        lock.withLock { readsFail = true }
    }

    func unlockFiles() {
        lock.withLock { readsFail = false }
    }

    func listing(id: UUID) throws -> BackupFolderListing {
        if lock.withLock({ readsFail }) {
            throw failure
        }
        return try base.listing(id: id)
    }

    func read(id: UUID) throws -> BackupSnapshotFiles {
        if lock.withLock({ readsFail }) {
            throw failure
        }
        return try base.read(id: id)
    }

    func delete(id: UUID) throws {
        lock.withLock { deletes += 1 }
        try base.delete(id: id)
    }

    func storedIDs() throws -> [UUID] { try base.storedIDs() }
    func loadStatus() throws -> BackupStatus { try base.loadStatus() }
    func saveStatus(_ status: BackupStatus) throws { try base.saveStatus(status) }
    func write(_ files: BackupSnapshotFiles, id: UUID, cloningFrom earlier: UUID?) throws {
        try base.write(files, id: id, cloningFrom: earlier)
    }
}

/// S81 (R5): an exported backup whose manifest has an `encryption` section added, shaped like an export from
/// PR #99's earlier build (c565212). The parameters are made up and nothing is encrypted; format 1 must report it
/// damaged.
func addingEncryptionSection(to archive: Data) throws -> Data {
    try rewritingManifest(of: archive) { object in
        object["encryption"] = [
            "algorithm": "AES-256-GCM",
            "keyDerivation": "PBKDF2-HMAC-SHA256",
            "iterations": 600_000,
            "salt": Data(repeating: 7, count: 16).base64EncodedString(),
        ]
    }
}

/// An exported backup with its `manifest.json` changed by `change`.
func rewritingManifest(of archive: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
    let archiving = FakeBackupArchiving()
    var files = try BackupArchiveSafety.files(from: archiving.entries(of: archive))
    guard let manifest = files["manifest.json"],
        var object = try JSONSerialization.jsonObject(with: manifest) as? [String: Any]
    else {
        throw BackupError.damaged
    }
    change(&object)
    files["manifest.json"] = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try archiving.archive(files)
}

/// The checked-in S81 sample: shaped like an encrypted export from PR #99's c565212 build, with arbitrary bytes
/// as its body. Tester copies the same file to the simulator for manual QA.
func oldEncryptedSample() throws -> Data {
    let url = try #require(
        Bundle.module.url(
            forResource: "Old Encrypted Sample",
            withExtension: "littleorbit-backup",
            subdirectory: "Fixtures",
        )
    )
    return try Data(contentsOf: url)
}

extension BackupsWindow {
    /// What SwiftUI does with the restore progress sheet the window asked for: its content appears, then it closes
    /// and `onDismiss` runs. A restore's error is presented only after that (Tester F1).
    func showAndCloseRestoreProgress() {
        restoreProgressAppeared()
        restoreProgressDismissed()
    }
}
