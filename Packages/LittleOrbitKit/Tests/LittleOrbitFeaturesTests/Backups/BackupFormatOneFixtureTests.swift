import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// Format 1 stays readable until it freezes with V1 (#174 review, Q9 conditions a and b): a backup `main` wrote at
/// 1f27b72, before budgets, decodes with no budgets, writes back byte for byte, keeps its fingerprint and restores.
/// Budgets that break the stores' rule make a backup damaged, and nothing is replaced (#174 B1).
@MainActor
@Suite("Format 1 before budgets (#174)")
struct BackupFormatOneFixtureTests {
    /// The checked-in folder, file by file. Its checksums are the tests' fake hashing, as the harness uses.
    private func fixture() throws -> BackupSnapshotFiles {
        let root = try #require(
            Bundle.module.url(forResource: "Format 1 Before Budgets", withExtension: nil, subdirectory: "Fixtures")
        )
        var files = BackupSnapshotFiles()
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }
            let path = String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
            files[path] = try Data(contentsOf: url)
        }
        return files
    }

    @Test("Q9 (a): it decodes with no budgets, and writes back byte for byte with the fingerprint it had")
    func decodesAsBefore() throws {
        let files = try fixture()
        let codec = BackupCodec(hashing: FakeBackupHashing())
        let contents = try codec.decode(files)
        #expect(contents.ledger.budgets.isEmpty)
        #expect(contents.ledger.accounts.count == 1)
        #expect(contents.ledger.transactions.count == 2)
        #expect(contents.ledger.attachments.count == 1)
        #expect(!contents.manifest.sections.contains(.budgets))
        let summary = try codec.summary(ofManifest: try #require(files[BackupFormat.manifestPath]))
        #expect(try codec.fingerprint(of: contents.ledger) == summary.fingerprint)
        let written = try codec.encode(contents)
        for path in files.paths where path != BackupFormat.manifestPath {
            #expect(written[path] == files[path], "\(path)")
        }
    }

    @Test("Q9 (a): it restores into the store as a picked file, with no budgets")
    func restores() async throws {
        let harness = try BackupHarness()
        let files = try fixture()
        let archive = try harness.archiving.archive(files)
        _ = try await harness.service.restore(.archive(.data(archive))) { _ in }
        let restored = try harness.repository.ledgerSnapshot()
        let expected = try BackupCodec(hashing: FakeBackupHashing()).decode(files).ledger
        #expect(BackupContents.canonical(restored) == BackupContents.canonical(expected))
        #expect(try harness.repository.budgets().isEmpty)
    }

    @Test("B1: a picked file with a budget repeating every 0 weeks is damaged, and the data stays as it was")
    func damagedBudgetIsRefused() async throws {
        let harness = try BackupHarness()
        let food = TransactionCategory(name: "Food", kind: .expense)
        try harness.repository.saveCategory(food)
        let before = try harness.repository.ledgerSnapshot()
        let budget = Budget(
            name: "Eating out",
            currencyCode: "INR",
            categoryIDs: [food.id],
            startDay: CalendarDay(year: 2026, month: 11, day: 1),
            recurrence: .custom(every: 0, unit: .week),
            limit: 8_000,
            createdAt: BackupHarness.morning,
        )
        var ledger = before
        ledger.budgets = [budget]
        let manifest = BackupManifest(
            kind: .manual,
            createdAt: BackupHarness.morning,
            nameIndex: 1,
            schemaVersion: "1.0.0",
            accountCount: ledger.accounts.count,
            transactionCount: 0,
            attachmentCount: 0,
        )
        let files = try BackupCodec(hashing: FakeBackupHashing())
            .encode(BackupContents(manifest: manifest, ledger: ledger))
        let archive = try harness.archiving.archive(files)
        await #expect(throws: BackupError.damaged) {
            try await harness.service.restore(.archive(.data(archive))) { _ in }
        }
        #expect(try harness.repository.ledgerSnapshot() == before)
    }
}
