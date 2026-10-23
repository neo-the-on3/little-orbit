import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// D195 over the real service: one folder per backup, exports in one file, and retention (L1–L18).
@MainActor
@Suite("Backup service: folders and retention", .timeLimit(.minutes(2)))
struct BackupFolderServiceTests {
    /// Changes the data and makes the day's automatic backup, one day later.
    private func dailyBackups(_ harness: BackupHarness, count: Int) async throws -> [BackupRecord] {
        var made: [BackupRecord] = []
        for day in 0..<count {
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
            if let record = try await harness.service.backUpAutomaticallyIfNeeded() {
                made.append(record)
            }
        }
        return made
    }

    @Test("At the defaults, 7 recent automatic backups and the month's first are kept; manual ones stay (L7, L10)")
    func pruning() async throws {
        let harness = try BackupHarness()
        let manual = try await harness.service.backUpNow()
        // 23 Oct to 31 Oct: the 7 most recent plus 23 Oct, October's keeper.
        let made = try await dailyBackups(harness, count: 9)
        let backups = try await harness.service.overview().backups
        let automatic = backups.filter { $0.kind == .automatic }.map(\.id)
        #expect(Set(automatic) == Set([made[0].id] + made.suffix(7).map(\.id)))
        #expect(backups.contains(manual))
        #expect(try harness.storedFiles().count == 9)
    }

    @Test("Damaged backups are never pruned or counted; the only restorable one stays (L32, L33)")
    func keepsTheOnlyRestorableBackup() async throws {
        let harness = try BackupHarness()
        let made = try await dailyBackups(harness, count: 4)
        for record in made.dropFirst() {
            try damage(harness.backupFolder(record.id).appendingPathComponent("shared.json"))
        }
        let plan = try await harness.service.cleanupPlan(for: BackupRetention(recentAutomatic: 1, monthlyMonths: 0))
        #expect(plan.backups.isEmpty)
        _ = try await harness.service.apply(plan)
        let remaining = try await harness.service.overview().backups
        #expect(Set(remaining.map(\.id)) == Set(made.map(\.id)))
        #expect(remaining.filter { $0.condition == .damaged }.count == 3)
        let restorable = try await harness.contents(.stored(made[0].id))
        #expect(!restorable.accounts.isEmpty)
    }

    private func damage(_ url: URL) throws {
        var data = try Data(contentsOf: url)
        data[data.startIndex] ^= 0x01
        try data.write(to: url)
    }

    @Test("Each backup is a folder named by its local date and time, with the D195.1 layout (L1, D209)")
    func folderLayout() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        // 2026-10-22 09:12:05 in Kolkata, zero-padded (D209).
        #expect(try harness.storedFiles() == ["2026-10-22-09-12"])
        let files = try harness.storage.read(id: backup.id)
        #expect(files.paths.contains("manifest.json"))
        #expect(files.paths.contains("shared.json"))
        #expect(
            files.paths.allSatisfy { path in
                ["manifest.json", "shared.json"].contains(path) || path.hasPrefix("accounts/")
                    || path.hasPrefix("transfers/") || path.hasPrefix("attachments/")
            }
        )
        // The size shown is the manifest total, the same as the exported folder (S61).
        let total = files.files.values.reduce(0) { $0 + $1.count }
        #expect(backup.byteSize == Int64(total))
    }

    @Test("A folder deleted by hand just leaves the list; the others still restore (L5, L6)")
    func deletedByHand() async throws {
        let harness = try BackupHarness()
        let first = try await harness.service.backUpNow()
        harness.advance(60)
        let second = try await harness.service.backUpNow()
        try FileManager.default.removeItem(at: harness.backupFolder(first.id))
        #expect(try await harness.service.overview().backups.map(\.id) == [second.id])
        let contents = try await harness.contents(.stored(second.id))
        #expect(contents.accounts.count == FeatureFixture.all().count)
    }

    @Test("A changed or missing file is damaged and changes nothing; an extra file is ignored (L4)")
    func damagedFolder() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        let folder = harness.backupFolder(backup.id)
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent(".DS_Store"))
        _ = try await harness.contents(.stored(backup.id))

        try damage(folder.appendingPathComponent("shared.json"))
        let before = try harness.repository.ledgerSnapshot()
        await #expect(throws: BackupError.damaged) { try await harness.contents(.stored(backup.id)) }
        try FileManager.default.removeItem(at: folder.appendingPathComponent("shared.json"))
        await #expect(throws: BackupError.damaged) { try await harness.contents(.stored(backup.id)) }
        #expect(try harness.repository.ledgerSnapshot() == before)
    }

    @Test("A folder whose manifest is unreadable or gone is listed as damaged, with its kind and date (L29, L37)")
    func damagedManifestIsListed() async throws {
        let harness = try BackupHarness()
        let first = try await harness.service.backUpNow()
        harness.advance(60)
        let second = try await harness.service.backUpNow()
        _ = try await harness.service.overview()
        try Data("{broken".utf8).write(to: harness.backupFolder(first.id).appendingPathComponent("manifest.json"))
        try FileManager.default.removeItem(at: harness.backupFolder(second.id).appendingPathComponent("manifest.json"))
        let backups = try await harness.service.overview().backups
        #expect(backups.map(\.id) == [second.id, first.id])
        #expect(backups.allSatisfy { $0.condition == .damaged && $0.kind == .manual })
        #expect(backups.map(\.createdAt) == [second.createdAt, first.createdAt])
        // Its size from the last good read, not 0 or the folder's remaining files (D202.1, L47).
        #expect(backups.map(\.byteSize) == [second.byteSize, first.byteSize])
        await #expect(throws: BackupError.damaged) { try await harness.contents(.stored(first.id)) }
        await #expect(throws: BackupError.damaged) { try await harness.service.exportBackup(id: second.id) }
        // Delete still works.
        try await harness.service.deleteBackup(id: first.id)
        #expect(try await harness.service.overview().backups.map(\.id) == [second.id])
    }

    @Test("An exported file with a changed, missing or unsafe entry is damaged and changes nothing (L4, L18)")
    func unsafeArchive() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        let files = try harness.storage.read(id: backup.id)
        let before = try harness.repository.ledgerSnapshot()
        func entries(_ files: BackupSnapshotFiles) -> [BackupArchiveEntry] {
            files.paths.map { BackupArchiveEntry(path: $0, kind: .file(files[$0] ?? Data())) }
        }
        var missing = files
        missing["shared.json"] = nil
        var changed = files
        changed["shared.json"] = Data("{}".utf8)
        let archives: [[BackupArchiveEntry]] = [
            entries(missing),
            entries(changed),
            entries(files) + [BackupArchiveEntry(path: "../escape.json", kind: .file(Data("x".utf8)))],
            entries(files) + [BackupArchiveEntry(path: "/etc/hosts", kind: .file(Data("x".utf8)))],
            entries(files) + [BackupArchiveEntry(path: "attachments/link", kind: .symbolicLink(target: "/etc"))],
            entries(files) + [BackupArchiveEntry(path: "attachments/hard", kind: .hardLink(target: "../x"))],
        ]
        for archive in archives {
            let data = try FakeBackupArchiving.crafted(archive)
            await #expect(throws: BackupError.damaged) { try await harness.contents(.file(data)) }
        }
        #expect(try harness.repository.ledgerSnapshot() == before)
        #expect(try harness.storedFiles() == [harness.backupFolder(backup.id).lastPathComponent])
    }

    @Test("N and M aren't in the backup, and a restore leaves them as they are (D195.4)")
    func settingsSurviveRestore() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        let shared = try #require(try harness.storage.read(id: backup.id)["shared.json"])
        let object = try #require(JSONSerialization.jsonObject(with: shared) as? [String: Any])
        #expect(
            Set(object.keys) == [
                "accounts", "categories", "payees", "tags", "sharedSettings", "importRules", "budgets",
                "scheduledItems", "reconciliationHistory", "unfiled",
            ]
        )
        harness.settings.setRetention(BackupRetention(recentAutomatic: 3, monthlyMonths: 2))
        let contents: BackupSource = .stored(backup.id)
        _ = try await harness.service.restore(contents) { _ in }
        #expect(harness.service.retention() == BackupRetention(recentAutomatic: 3, monthlyMonths: 2))
    }

    @Test("Lowering N counts exactly what it deletes, and deletes only that once applied (L12, L13)")
    func loweringRetention() async throws {
        let harness = try BackupHarness()
        let made = try await dailyBackups(harness, count: 8)
        let lower = BackupRetention(recentAutomatic: 3, monthlyMonths: 12)
        let plan = try await harness.service.cleanupPlan(for: lower)
        // 23 Oct is October's keeper; of 24–30 Oct only the newest 3 stay.
        #expect(plan.backups.map(\.id) == made[1..<5].map(\.id))
        #expect(try await harness.service.overview().backups.count == 8)
        #expect(harness.service.retention() == .default)

        let deleted = try await harness.service.apply(plan)
        #expect(deleted.map(\.id) == plan.backups.map(\.id))
        #expect(harness.service.retention() == lower)
        #expect(
            Set(try await harness.service.overview().backups.map(\.id)) == Set([made[0].id] + made.suffix(3).map(\.id))
        )
    }

    @Test("Raising N or M deletes nothing and brings nothing back (L14)")
    func raisingRetention() async throws {
        let harness = try BackupHarness()
        _ = try await dailyBackups(harness, count: 9)
        let before = try await harness.service.overview().backups
        let higher = BackupRetention(recentAutomatic: 10, monthlyMonths: 12)
        let plan = try await harness.service.cleanupPlan(for: higher)
        #expect(plan.backups.isEmpty)
        #expect(try await harness.service.apply(plan).isEmpty)
        #expect(try await harness.service.overview().backups == before)
        #expect(harness.service.retention() == higher)
    }

    @Test("A plan never deletes more than it counted, even if more would go now (L13)")
    func applyDeletesOnlyWhatWasCounted() async throws {
        let harness = try BackupHarness()
        _ = try await dailyBackups(harness, count: 8)
        let lower = BackupRetention(recentAutomatic: 3, monthlyMonths: 0)
        let plan = try await harness.service.cleanupPlan(for: lower)
        let partial = BackupCleanupPlan(retention: lower, backups: Array(plan.backups.prefix(1)))
        #expect(try await harness.service.apply(partial).map(\.id) == partial.backups.map(\.id))
        #expect(try await harness.service.overview().backups.count == 7)
    }

    @Test("If a backup's manifest can't be read, that backup gets its own row and nothing is pruned (R3, D208.3, D214)")
    func lockedFiles() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = try LockedFilesStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        let backup = try await harness.service.backUpNow()
        storage.lockFiles()

        // Never listed this session, so D214's unreadable row; the list itself loads (only the Backups folder or
        // status.json give Couldn’t Load Backups, D211.5).
        let listed = try await harness.service.overview().backups
        #expect(listed.map(\.id) == [backup.id])
        #expect(listed.first?.condition == .unreadable)
        await #expect(throws: BackupError.cleanupBlocked) {
            try await harness.service.cleanupPlan(for: BackupRetention(recentAutomatic: 1, monthlyMonths: 0))
        }
        #expect(storage.deletes == 0)
        #expect(try storage.base.storedIDs().count == 1)
    }
}
