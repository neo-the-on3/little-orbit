import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// D209: backup folders are named `yyyy-MM-dd-HH-mm` in the device's time zone, but nothing reads a date from a
/// name. Identity is the manifest's ID, and order and retention come from its `createdAt` (L60–L63).
@MainActor
@Suite("Backup folders: names by local date and time (D209)", .timeLimit(.minutes(2)))
struct BackupFolderNamingTests {
    private static let newYork = TimeZone(identifier: "America/New_York") ?? .gmt
    private static let losAngeles = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

    private func change(_ harness: BackupHarness, _ name: String, order: Double) throws {
        try harness.repository.saveAccount(
            Account(name: name, type: .cash, currencyCode: "INR", openingBalance: 1, sortOrder: order)
        )
    }

    @Test("Two backups in one minute get the name and then -2; neither overwrites the other (D209 item 2, L61)")
    func sameMinute() async throws {
        let harness = try BackupHarness()
        let first = try await harness.service.backUpNow()
        harness.advance(20)
        let second = try await harness.service.backUpNow()
        #expect(try harness.storedFiles() == ["2026-10-22-09-12", "2026-10-22-09-12-2"])
        #expect(harness.backupFolder(first.id).lastPathComponent == "2026-10-22-09-12")
        #expect(harness.backupFolder(second.id).lastPathComponent == "2026-10-22-09-12-2")
        let backups = try await harness.service.overview().backups
        #expect(backups.map(\.id) == [second.id, first.id])
        #expect(backups.allSatisfy { $0.condition != .damaged })
        _ = try await harness.contents(.stored(first.id))
        _ = try await harness.contents(.stored(second.id))
    }

    @Test("A folder already using the name is never reused: the backup takes -2 and the folder is left as it was")
    func takenName() async throws {
        let harness = try BackupHarness()
        try FileManager.default.createDirectory(at: harness.folder, withIntermediateDirectories: true)
        let byHand = harness.folder.appendingPathComponent("2026-10-22-09-12", isDirectory: true)
        try FileManager.default.createDirectory(at: byHand, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: byHand.appendingPathComponent("note.txt"))
        let backup = try await harness.service.backUpNow()
        #expect(harness.backupFolder(backup.id).lastPathComponent == "2026-10-22-09-12-2")
        #expect(try FileManager.default.contentsOfDirectory(atPath: byHand.path) == ["note.txt"])
        // The folder without a manifest is still listed, as Damaged (D209 item 3, L62).
        let backups = try await harness.service.overview().backups
        #expect(backups.count == 2)
        #expect(backups.first { $0.id == backup.id }?.condition != .damaged)
        #expect(backups.first { $0.id != backup.id }?.condition == .damaged)
    }

    @Test("After the DST fall-back a later backup sorts first by name, yet the list follows createdAt (D209 item 3)")
    func fallBackListOrder() async throws {
        let harness = try BackupHarness(zone: Self.newYork)
        // 2026-11-01 01:50 EDT, then 01:10 EST, twenty minutes later.
        harness.clock.now = Date(timeIntervalSince1970: 1_793_512_200)
        let earlier = try await harness.service.backUpNow()
        harness.clock.now = Date(timeIntervalSince1970: 1_793_513_400)
        let later = try await harness.service.backUpNow()
        #expect(harness.backupFolder(earlier.id).lastPathComponent == "2026-11-01-01-50")
        #expect(harness.backupFolder(later.id).lastPathComponent == "2026-11-01-01-10")
        #expect(try harness.storedFiles() == ["2026-11-01-01-10", "2026-11-01-01-50"])
        let backups = try await harness.service.overview().backups
        #expect(backups.map(\.id) == [later.id, earlier.id])
        #expect(backups.map(\.createdAt) == [later.createdAt, earlier.createdAt])
    }

    @Test("Retention keeps the newest by createdAt even when its folder name sorts earlier (D209 item 3, L7)")
    func retentionFollowsCreatedAt() async throws {
        let harness = try BackupHarness()
        // 2026-11-04 10:00 in Kolkata.
        harness.clock.now = Date(timeIntervalSince1970: 1_793_766_600)
        try change(harness, "Before the flight", order: 20)
        let older = try #require(try await harness.service.backUpAutomaticallyIfNeeded())
        // Four hours later, 00:30 the same date in Los Angeles: a later backup with an earlier-sorting name.
        harness.move(to: Self.losAngeles)
        harness.clock.now = Date(timeIntervalSince1970: 1_793_781_000)
        try change(harness, "After the flight", order: 21)
        let newer = try #require(try await harness.service.backUpAutomaticallyIfNeeded())
        #expect(harness.backupFolder(older.id).lastPathComponent == "2026-11-04-10-00")
        #expect(harness.backupFolder(newer.id).lastPathComponent == "2026-11-04-00-30")
        let plan = try await harness.service.cleanupPlan(for: BackupRetention(recentAutomatic: 1, monthlyMonths: 0))
        #expect(plan.backups.map(\.id) == [older.id])
        _ = try await harness.service.apply(plan)
        #expect(try await harness.service.overview().backups.map(\.id) == [newer.id])
        #expect(try harness.storedFiles() == ["2026-11-04-00-30"])
    }

    @Test("The manifest keeps the backup's ID, which the list and the export lock use (D209 item 4)")
    func manifestID() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        let data = try Data(contentsOf: harness.backupFolder(backup.id).appendingPathComponent("manifest.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let head = try #require(json["backup"] as? [String: Any])
        #expect(head["id"] as? String == backup.id.uuidString)
        // A relaunch over the same folder finds the same ID.
        let relaunched = try FileBackupStorage(folder: harness.folder)
        #expect(try relaunched.storedIDs() == [backup.id])
    }

    @Test("A dev build's folder named by its ID, with no ID in its manifest, is still listed and restorable (item 5)")
    func legacyFolder() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        let named = harness.backupFolder(backup.id)
        let legacy = harness.folder.appendingPathComponent(backup.id.uuidString, isDirectory: true)
        try FileManager.default.moveItem(at: named, to: legacy)
        let manifestURL = legacy.appendingPathComponent("manifest.json")
        var json = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        var head = try #require(json["backup"] as? [String: Any])
        head["id"] = nil
        json["backup"] = head
        try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)

        let relaunched = try BackupHarness(
            storage: FileBackupStorage(folder: harness.folder, timeZone: { [zone = harness.zone] in zone })
        )
        let backups = try await relaunched.service.overview().backups
        #expect(backups.map(\.id) == [backup.id])
        #expect(backups.first?.condition != .damaged)
        let contents = try await relaunched.contents(.stored(backup.id))
        #expect(!contents.accounts.isEmpty)
        // A new backup beside it gets a date-and-time name; the old folder isn't renamed.
        relaunched.advance(120)
        let next = try await relaunched.service.backUpNow()
        #expect(relaunched.backupFolder(next.id).lastPathComponent == "2026-10-22-09-14")
        #expect(
            Set(try FileManager.default.contentsOfDirectory(atPath: harness.folder.path))
                .isSuperset(of: [
                    backup.id.uuidString, "2026-10-22-09-14",
                ])
        )
        #expect(FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test("A folder renamed by hand, or copied, keeps its date, order and retention; one with no manifest is Damaged")
    func renamedFolders() async throws {
        let harness = try BackupHarness()
        // 3, 4 and 5 Oct 2026 (L62).
        harness.clock.now = Date(timeIntervalSince1970: 1_791_001_800)
        var made: [BackupRecord] = []
        for day in 0..<3 {
            try change(harness, "Day \(day)", order: Double(30 + day))
            made.append(try #require(try await harness.service.backUpAutomaticallyIfNeeded()))
            harness.advance(86_400)
        }
        let before = try await harness.service.overview().backups
        let retention = BackupRetention(recentAutomatic: 1, monthlyMonths: 0)
        let planBefore = try await harness.service.cleanupPlan(for: retention)
        let manager = FileManager.default
        try manager.moveItem(
            at: harness.backupFolder(made[0].id),
            to: harness.folder.appendingPathComponent("2026-12-31-23-59", isDirectory: true),
        )
        try manager.moveItem(
            at: harness.backupFolder(made[1].id),
            to: harness.folder.appendingPathComponent("copy of backup", isDirectory: true),
        )
        let after = try await harness.service.overview().backups
        #expect(after.map(\.id) == before.map(\.id))
        #expect(after.map(\.createdAt) == before.map(\.createdAt))
        #expect(try await harness.service.cleanupPlan(for: retention).backups.map(\.id) == planBefore.backups.map(\.id))
        _ = try await harness.contents(.stored(made[1].id))

        // `old`, with no manifest, is listed as Damaged and nothing is renamed (L63).
        try manager.createDirectory(
            at: harness.folder.appendingPathComponent("old", isDirectory: true),
            withIntermediateDirectories: true,
        )
        let listed = try await harness.service.overview().backups
        #expect(listed.count == 4)
        let old = try #require(listed.first { !made.map(\.id).contains($0.id) })
        #expect(old.condition == .damaged)
        #expect(
            Set(try harness.storedFiles()) == [
                "2026-12-31-23-59", "copy of backup", "old",
                harness.backupFolder(made[2].id).lastPathComponent,
            ]
        )
        try await harness.service.deleteBackup(id: old.id)
        try await harness.service.deleteBackup(id: made[1].id)
        #expect(
            Set(try harness.storedFiles()) == ["2026-12-31-23-59", harness.backupFolder(made[2].id).lastPathComponent]
        )
    }
}
