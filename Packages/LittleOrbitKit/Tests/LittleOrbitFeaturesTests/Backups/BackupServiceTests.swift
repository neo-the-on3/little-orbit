import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// #40 acceptance over the real service, an in-memory ledger and real files in a temporary folder.
@MainActor
@Suite("Backup service")
struct BackupServiceTests {
    @Test("Back Up Now stores a manual backup with the visible counts")
    func backUpNow() async throws {
        let harness = try BackupHarness()
        let record = try await harness.service.backUpNow()
        #expect(record.kind == .manual)
        #expect(record.accountCount == FeatureFixture.all().count)
        #expect(record.byteSize > 0)
        #expect(try harness.storedFiles().count == 1)
        #expect(try harness.service.overview().backups == [record])
    }

    @Test("Restore puts the balances back and saves a Before restore backup first (S54, S55)")
    func restore() async throws {
        let harness = try BackupHarness()
        let accounts = try harness.repository.accounts()
        let balances = try accounts.map { try harness.repository.balance(of: $0.id) }
        let backup = try await harness.service.backUpNow()

        harness.advance(120)
        try harness.repository.saveTransaction(Transaction(amount: 999, accountID: accounts[0].id))
        try harness.repository.deleteAccount(id: accounts[1].id)

        let contents = try await harness.service.openBackup(.stored(backup.id), password: nil)
        var steps: [BackupRestoreStep] = []
        let before = try await harness.service.restore(contents) { steps.append($0) }

        #expect(before.kind == .beforeRestore)
        #expect(steps == [.savingCurrentData, .replacingData, .finished])
        #expect(try accounts.map { try harness.repository.balance(of: $0.id) } == balances)
        #expect(try harness.service.overview().backups.map(\.kind) == [.beforeRestore, .manual])
    }

    @Test("The Before restore backup restores the data from before the restore (S55)")
    func undoRestore() async throws {
        let harness = try BackupHarness()
        let account = try #require(try harness.repository.accounts().first)
        let backup = try await harness.service.backUpNow()
        harness.advance(60)
        try harness.repository.saveTransaction(Transaction(amount: 50, accountID: account.id))
        let edited = try harness.repository.balance(of: account.id)

        let old = try await harness.service.openBackup(.stored(backup.id), password: nil)
        let before = try await harness.service.restore(old) { _ in }
        harness.advance(60)
        let undo = try await harness.service.openBackup(.stored(before.id), password: nil)
        _ = try await harness.service.restore(undo) { _ in }

        #expect(try harness.repository.balance(of: account.id) == edited)
    }

    @Test("No automatic backup right after a restore, until the data changes (S53)")
    func automaticAfterRestore() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        try harness.repository.saveTransaction(
            Transaction(amount: 10, accountID: try #require(try harness.repository.accounts().first).id)
        )
        let contents = try await harness.service.openBackup(.stored(backup.id), password: nil)
        _ = try await harness.service.restore(contents) { _ in }
        harness.advance(86_400)
        #expect(try await harness.service.backUpAutomaticallyIfNeeded() == nil)

        try harness.repository.saveAccount(
            Account(name: "New Account", type: .cash, currencyCode: "INR", openingBalance: 1, sortOrder: 9)
        )
        #expect(try await harness.service.backUpAutomaticallyIfNeeded()?.kind == .automatic)
    }

    @Test("One automatic backup a day, and none when nothing changed (S1, S2, S4)")
    func automaticOncePerDay() async throws {
        let harness = try BackupHarness()
        #expect(try await harness.service.backUpAutomaticallyIfNeeded()?.kind == .automatic)
        try harness.repository.saveAccount(
            Account(name: "Second", type: .cash, currencyCode: "INR", openingBalance: 1, sortOrder: 9)
        )
        harness.advance(3_600)
        #expect(try await harness.service.backUpAutomaticallyIfNeeded() == nil)
        harness.advance(86_400)
        #expect(try await harness.service.backUpAutomaticallyIfNeeded() != nil)
        harness.advance(86_400)
        #expect(try await harness.service.backUpAutomaticallyIfNeeded() == nil)
    }

    @Test("Only 14 automatic backups are kept; manual ones stay (S56, S57)")
    func pruning() async throws {
        let harness = try BackupHarness()
        let manual = try await harness.service.backUpNow()
        for day in 0..<16 {
            harness.advance(86_400)
            try harness.repository.saveAccount(
                Account(
                    name: "Day \(day)",
                    type: .cash,
                    currencyCode: "INR",
                    openingBalance: 1,
                    sortOrder: Double(10 + day),
                )
            )
            _ = try await harness.service.backUpAutomaticallyIfNeeded()
        }
        let backups = try harness.service.overview().backups
        #expect(backups.filter { $0.kind == .automatic }.count == 14)
        #expect(backups.contains(manual))
        #expect(try harness.storedFiles().count == 15)
    }

    @Test("A full disk leaves no file, prunes nothing and says so until the next backup (S58)")
    func notEnoughStorage() async throws {
        let full = FullDiskStorage()
        let harness = try BackupHarness(storage: full)
        await #expect(throws: BackupError.notEnoughStorage) { try await harness.service.backUpNow() }
        let overview = try harness.service.overview()
        #expect(overview.backups.isEmpty)
        #expect(overview.lastFailure == .notEnoughStorage)
    }

    @Test("The failure clears with the next successful backup")
    func failureClears() async throws {
        let harness = try BackupHarness()
        var catalog = try harness.storage.loadCatalog()
        catalog.lastFailure = .notEnoughStorage
        try harness.storage.saveCatalog(catalog)
        _ = try await harness.service.backUpNow()
        #expect(try harness.service.overview().lastFailure == nil)
    }

    @Test("Two backups in one minute export with the stored index, named ' 2' (D173.11)")
    func exportNames() async throws {
        let harness = try BackupHarness()
        let first = try await harness.service.backUpNow()
        harness.advance(20)
        let second = try await harness.service.backUpNow()
        let presentation = BackupPresentation(timeZone: harness.zone, device: .iPhone)
        let firstExport = try await harness.service.exportBackup(id: first.id, password: nil)
        let secondExport = try await harness.service.exportBackup(id: second.id, password: nil)
        #expect(firstExport.record == first)
        #expect(presentation.fileName(for: firstExport.record) == "little-orbit 2026-10-22 0912.littleorbit-backup")
        #expect(presentation.fileName(for: secondExport.record) == "little-orbit 2026-10-22 0912 2.littleorbit-backup")
    }

    @Test("An exported encrypted file restores only with its password (S49)")
    func encryptedExport() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        let export = try await harness.service.exportBackup(id: backup.id, password: "correct horse")
        #expect(export.isEncrypted)
        await #expect(throws: BackupError.passwordRequired) {
            try await harness.service.openBackup(.file(export.data), password: nil)
        }
        await #expect(throws: BackupError.incorrectPassword) {
            try await harness.service.openBackup(.file(export.data), password: "wrong horse")
        }
        let contents = try await harness.service.openBackup(.file(export.data), password: "correct horse")
        #expect(contents.accounts.count == FeatureFixture.all().count)
    }

    @Test("A damaged file changes nothing (S50)")
    func damagedFile() async throws {
        let harness = try BackupHarness()
        let before = try harness.repository.ledgerSnapshot()
        await #expect(throws: BackupError.damaged) {
            try await harness.service.openBackup(.file(Data("not a backup".utf8)), password: nil)
        }
        #expect(try harness.repository.ledgerSnapshot() == before)
    }

    @Test("Delete removes the file and the row; the oldest backup can be deleted too (S51)")
    func delete() async throws {
        let harness = try BackupHarness()
        let first = try await harness.service.backUpNow()
        harness.advance(60)
        _ = try await harness.service.backUpNow()
        try harness.service.deleteBackup(id: first.id)
        #expect(try harness.service.overview().backups.count == 1)
        #expect(try harness.storedFiles().count == 1)
        #expect(throws: BackupError.notFound) { try harness.service.deleteBackup(id: first.id) }
    }

    @Test("A new, empty ledger gets no automatic backup until it has data (D179.3)")
    func emptyLedger() async throws {
        let repository = InMemoryLedgerRepository()
        try repository.seedDefaultCategories()
        let harness = try BackupHarness(repository: repository)
        #expect(try await harness.service.backUpAutomaticallyIfNeeded() == nil)
        #expect(try harness.service.overview().backups.isEmpty)

        try repository.saveAccount(
            Account(name: "Wallet", type: .cash, currencyCode: "INR", openingBalance: 0, sortOrder: 1)
        )
        #expect(try await harness.service.backUpAutomaticallyIfNeeded()?.kind == .automatic)
    }

    @Test("A restore signals that the ledger was replaced, and Accounts reloads (B3)")
    func ledgerReplacedSignal() async throws {
        let harness = try BackupHarness()
        let accounts = AccountsFeature(
            useCases: FeatureFixture.useCases(harness.repository),
            ledgerChanges: harness.changes,
        )
        accounts.accounts.load()
        let before = accounts.accounts.assets.count + accounts.accounts.credit.count
        let backup = try await harness.service.backUpNow()
        try harness.repository.saveAccount(
            Account(name: "Added After", type: .cash, currencyCode: "INR", openingBalance: 1, sortOrder: 99)
        )
        accounts.accounts.load()
        #expect(accounts.accounts.assets.count + accounts.accounts.credit.count == before + 1)

        let contents = try await harness.service.openBackup(.stored(backup.id), password: nil)
        _ = try await harness.service.restore(contents) { _ in }

        #expect(harness.changes.replacements == 1)
        #expect(accounts.accounts.assets.count + accounts.accounts.credit.count == before)
    }

    @Test("A failed replace leaves the data as it was and keeps the Before restore backup (N4)")
    func failedReplace() async throws {
        let harness = try BackupHarness(source: { FailingReplaceSource($0) })
        let backup = try await harness.service.backUpNow()
        let before = try harness.repository.ledgerSnapshot()
        let contents = try await harness.service.openBackup(.stored(backup.id), password: nil)
        await #expect(throws: CocoaError.self) { try await harness.service.restore(contents) { _ in } }
        #expect(try harness.repository.ledgerSnapshot() == before)
        #expect(try harness.service.overview().backups.map(\.kind) == [.beforeRestore, .manual])
        #expect(harness.changes.replacements == 0)
    }

    @Test("A full disk while saving the Before restore backup aborts the restore, changing nothing (N4)")
    func fullDiskBeforeRestore() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("filling-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = try FillingDiskStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        let backup = try await harness.service.backUpNow()
        try harness.repository.saveAccount(
            Account(name: "Unsaved", type: .cash, currencyCode: "INR", openingBalance: 1, sortOrder: 99)
        )
        let current = try harness.repository.ledgerSnapshot()
        let contents = try await harness.service.openBackup(.stored(backup.id), password: nil)
        storage.fill()
        await #expect(throws: BackupError.notEnoughStorage) { try await harness.service.restore(contents) { _ in } }
        #expect(try harness.repository.ledgerSnapshot() == current)
        #expect(try harness.service.overview().backups.map(\.id) == [backup.id])
        #expect(harness.changes.replacements == 0)
    }

    @Test("An unreadable catalog is rebuilt from the stored backups (N3)")
    func rebuildCatalog() async throws {
        let harness = try BackupHarness()
        let first = try await harness.service.backUpNow()
        harness.advance(20)
        let second = try await harness.service.backUpNow()
        try Data("{broken".utf8).write(to: harness.folder.appendingPathComponent("catalog.json"))

        let rebuilt = try harness.service.overview().backups
        #expect(rebuilt.map(\.id) == [second.id, first.id])
        #expect(rebuilt.map(\.nameIndex) == [2, 1])
        #expect(rebuilt.first?.fingerprint == second.fingerprint)
        // Automatic backups keep working, and unchanged data is still recognised.
        harness.advance(86_400)
        #expect(try await harness.service.backUpAutomaticallyIfNeeded() == nil)
    }
}
