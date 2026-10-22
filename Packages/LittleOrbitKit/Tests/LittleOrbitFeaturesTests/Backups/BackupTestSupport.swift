import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence

/// A backup service over an in-memory ledger and a real file store in a temporary folder, with a settable clock.
@MainActor
final class BackupHarness {
    let repository: InMemoryLedgerRepository
    let folder: URL
    let storage: any BackupStorage
    let clock = BackupClock()
    let zone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
    let changes = LedgerChanges()
    let service: BackupService

    /// 2026-10-22 09:12:05 IST.
    static let morning = Date(timeIntervalSince1970: 1_792_640_525)

    /// `source` defaults to `repository`; tests pass a failing wrapper.
    init(
        repository: InMemoryLedgerRepository? = nil,
        storage: (any BackupStorage)? = nil,
        source: ((InMemoryLedgerRepository) -> any LedgerBackupSource)? = nil,
    ) throws {
        let repository = try repository ?? FeatureFixture.repository()
        self.repository = repository
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-tests-\(UUID().uuidString)", isDirectory: true)
        self.storage = try storage ?? FileBackupStorage(folder: folder)
        let clock = clock
        let zone = zone
        service = BackupService(
            source: source?(repository) ?? repository,
            storage: self.storage,
            cryptography: FakeBackupCryptography(),
            changes: changes,
            schemaVersion: "1.0.0",
            now: { clock.now },
            timeZone: { zone },
        )
    }

    var now: Date {
        clock.now
    }

    func advance(_ seconds: TimeInterval) {
        clock.now += seconds
    }

    func storedFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(BackupFormat.fileExtension) }
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

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }
}

@MainActor
final class BackupClock {
    var now = BackupHarness.morning
}

/// A disk that's full: every write fails without leaving a file.
final class FullDiskStorage: BackupStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var catalog = BackupCatalog()

    func loadCatalog() throws -> BackupCatalog {
        lock.withLock { catalog }
    }

    func saveCatalog(_ catalog: BackupCatalog) throws {
        lock.withLock { self.catalog = catalog }
    }

    func write(_ data: Data, id: UUID) throws -> Int64 {
        throw BackupError.notEnoughStorage
    }

    func read(id: UUID) throws -> Data {
        throw BackupError.notFound
    }

    func delete(id: UUID) throws {}

    func storedIDs() throws -> [UUID] {
        []
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

/// A real file store whose disk can fill up between writes.
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

    func loadCatalog() throws -> BackupCatalog { try base.loadCatalog() }
    func saveCatalog(_ catalog: BackupCatalog) throws { try base.saveCatalog(catalog) }
    func read(id: UUID) throws -> Data { try base.read(id: id) }
    func delete(id: UUID) throws { try base.delete(id: id) }
    func storedIDs() throws -> [UUID] { try base.storedIDs() }

    func write(_ data: Data, id: UUID) throws -> Int64 {
        if lock.withLock({ full }) {
            throw BackupError.notEnoughStorage
        }
        return try base.write(data, id: id)
    }
}

/// A ledger whose replace fails, as a failed SwiftData save would: nothing changes.
@MainActor
final class FailingReplaceSource: LedgerBackupSource {
    private let base: InMemoryLedgerRepository

    init(_ base: InMemoryLedgerRepository) {
        self.base = base
    }

    func ledgerSnapshot() throws -> LedgerSnapshot {
        try base.ledgerSnapshot()
    }

    func replaceLedger(with snapshot: LedgerSnapshot) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}
