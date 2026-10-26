import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// "Show upcoming" is a shared preference included in backups (D80, D348.3): each backup writes its current value,
/// a restore puts it back, and a backup without it, or with an older range, restores as On (D348.4). Format 1.
@MainActor
@Suite("Show upcoming in backups (D348)", .timeLimit(.minutes(2)))
struct BackupShowUpcomingTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    private func repository() throws -> InMemoryLedgerRepository {
        try F.repository([F.expense(250, on: F.date(2026, 10, 10))])
    }

    private func sharedJSON(_ harness: BackupHarness, _ id: UUID) throws -> String {
        let files = try harness.storage.files(id: id)
        let data = try #require(try files.data(at: BackupFormat.sharedPath))
        return try #require(String(bytes: data, encoding: .utf8))
    }

    @Test("A backup writes Off; turning it On and restoring that backup brings Off back, in format 1")
    func roundTripOff() async throws {
        let setting = InMemoryShowUpcomingSetting(showsUpcoming: false)
        let harness = try BackupHarness(
            repository: try repository(),
            sharedSettings: ShowUpcomingBackupSettings(store: setting),
        )
        let backup = try await harness.service.backUpNow()
        let contents = try await harness.contents(.stored(backup.id))
        #expect(contents.sharedSettings.showUpcoming == false)
        #expect(try sharedJSON(harness, backup.id).contains("\"showUpcoming\":false"))
        #expect(BackupFormat.currentVersion == 1)

        setting.showsUpcoming = true
        _ = try await harness.service.restore(.stored(backup.id)) { _ in }
        #expect(setting.showsUpcoming == false)
    }

    @Test("A backup writes On, and restoring it over Off brings On back")
    func roundTripOn() async throws {
        let setting = InMemoryShowUpcomingSetting()
        let harness = try BackupHarness(
            repository: try repository(),
            sharedSettings: ShowUpcomingBackupSettings(store: setting),
        )
        let backup = try await harness.service.backUpNow()
        #expect(try await harness.contents(.stored(backup.id)).sharedSettings.showUpcoming == true)
        setting.showsUpcoming = false
        _ = try await harness.service.restore(.stored(backup.id)) { _ in }
        #expect(setting.showsUpcoming)
    }

    @Test("A backup made before D348, with no Show upcoming, restores as On")
    func olderBackupRestoresOn() async throws {
        let older = try BackupHarness(repository: try repository())
        let backup = try await older.service.backUpNow()
        #expect(try await older.contents(.stored(backup.id)).sharedSettings.showUpcoming == nil)
        #expect(try !sharedJSON(older, backup.id).contains("showUpcoming"))

        let setting = InMemoryShowUpcomingSetting(showsUpcoming: false)
        let current = try BackupHarness(
            repository: try repository(),
            storage: older.storage,
            sharedSettings: ShowUpcomingBackupSettings(store: setting),
        )
        _ = try await current.service.restore(.stored(backup.id)) { _ in }
        #expect(setting.showsUpcoming)
    }

    @Test("D348.4: an older Next month, Next quarter or Next year range reads as On; Off and false read as Off")
    func olderRangesReadOn() throws {
        func read(_ value: String) throws -> Bool? {
            let json = Data("{\"showUpcoming\":\(value)}".utf8)
            return try JSONDecoder().decode(BackupSharedSettings.self, from: json).showUpcoming
        }
        #expect(try read("\"nextMonth\"") == true)
        #expect(try read("\"nextQuarter\"") == true)
        #expect(try read("\"nextYear\"") == true)
        #expect(try read("\"off\"") == false)
        #expect(try read("false") == false)
        #expect(try read("true") == true)
        #expect(try JSONDecoder().decode(BackupSharedSettings.self, from: Data("{}".utf8)).showUpcoming == nil)
    }

    @Test("The Settings switch shows the restored value")
    func switchFollowsRestore() async throws {
        let setting = InMemoryShowUpcomingSetting(showsUpcoming: false)
        let harness = try BackupHarness(
            repository: try repository(),
            sharedSettings: ShowUpcomingBackupSettings(store: setting),
        )
        let updates = LedgerUpdates()
        updates.follow(harness.changes)
        let model = ScheduledUpcomingSettingsModel(store: setting, updates: updates)
        let backup = try await harness.service.backUpNow()
        model.showsUpcoming = true
        #expect(setting.showsUpcoming)
        _ = try await harness.service.restore(.stored(backup.id)) { _ in }
        #expect(!model.showsUpcoming)
        #expect(!setting.showsUpcoming)
    }
}
