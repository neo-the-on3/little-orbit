import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

/// Tech Architect B3: a cloned file is only as good as the earlier backup's file, so a new backup that fails its
/// check after cloning is written again without clones, and the earlier backup is marked 'Damaged'. A restore never
/// replaces data unless its Before restore backup checked out (D63).
@MainActor
@Suite("Backups never trust a bad copy")
struct BackupSafetyCopyTests {
    private static let size = BackupChunk.size * 5 / 2

    @Test("A same-size change in the earlier backup isn't cloned on: the new backup is rewritten, the earlier Damaged")
    func damagedEarlierIsNotCloned() async throws {
        let fixture = try StreamingFixture(size: Self.size)
        let first = try await fixture.harness.service.backUpNow()
        let path = StreamingFixture.path(fixture.attachments[0].id)
        let url = fixture.backupFolder(first.id).appendingPathComponent(path)
        var bytes = try Data(contentsOf: url)
        bytes[0] ^= 0xFF
        try bytes.write(to: url)

        fixture.harness.advance(60)
        let second = try await fixture.harness.service.backUpNow()

        #expect(second.condition == .restorable)
        // Written once with both files cloned, then again with nothing cloned.
        #expect(fixture.storage.recorded.unchanged.suffix(2).map(\.count) == [2, 0])
        #expect(try fixture.storage.base.read(id: second.id)[path] == fixture.attachments[0].data)
        let listed = try await fixture.harness.service.overview().backups
        #expect(listed.map(\.id) == [second.id, first.id])
        #expect(listed.map(\.condition) == [.restorable, .damaged])

        // The next backup clones from the good one, and nothing piles up.
        fixture.harness.advance(60)
        let third = try await fixture.harness.service.backUpNow()
        #expect(third.condition == .restorable)
        #expect(fixture.storage.recorded.unchanged.last?.count == 2)
        #expect(fixture.folders.count == 3)
    }

    @Test("A restore whose Before restore backup is damaged stops with the data unchanged and says so")
    func damagedBeforeRestoreStops() async throws {
        let fixture = try StreamingFixture(size: Self.size)
        let backup = try await fixture.harness.service.backUpNow()
        try fixture.source.base.deleteAttachment(id: fixture.attachments[1].id)
        let current = try fixture.source.base.ledgerSnapshot()
        let window = fixture.harness.window()
        try await window.model.load()
        fixture.harness.advance(60)
        await window.requestRestore(backup.id)
        let prompt = try #require(window.restorePrompt)
        // The Before restore backup hashes one attachment from bytes that then change, so its check fails.
        fixture.source.hooks.flip(fixture.source.hooks.calls + 1)

        await window.confirmRestore(prompt)

        #expect(window.alert?.title == "Couldn’t Restore")
        #expect(
            window.alert?.message
                == "The backup of your current data didn’t pass its check, so nothing was replaced. Your data hasn’t changed."
        )
        #expect(window.toast == nil)
        #expect(try fixture.source.base.ledgerSnapshot() == current)
        #expect(fixture.source.restoredSnapshotBytes.isEmpty)
        #expect(fixture.source.wholeLedgerReplaces == 0)
        #expect(fixture.harness.changes.replacements == 0)
        let listed = try await fixture.harness.service.overview().backups
        #expect(listed.map(\.kind) == [.beforeRestore, .manual])
        #expect(listed.map(\.condition) == [.damaged, .restorable])
        #expect(fixture.stagingIsEmpty)
    }

    @Test("With a good Before restore backup the restore goes ahead")
    func goodBeforeRestoreRestores() async throws {
        let fixture = try StreamingFixture(size: 10)
        let backup = try await fixture.harness.service.backUpNow()
        try fixture.source.base.deleteAttachment(id: fixture.attachments[1].id)
        fixture.harness.advance(60)
        let before = try await fixture.harness.service.restore(.stored(backup.id)) { _ in }
        #expect(before.condition == .restorable)
        #expect(fixture.harness.changes.replacements == 1)
    }
}
