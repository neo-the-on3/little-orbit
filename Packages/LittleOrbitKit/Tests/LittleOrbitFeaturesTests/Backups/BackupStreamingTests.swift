import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

/// Tech Architect B1: Back Up Now, a restore from the list and a restore from a picked file never hold an
/// attachment whole in memory. The bytes go through in chunks of at most `BackupChunk.size`, unchanged files are
/// cloned instead of read, and a restore hands each attachment to the store from a file, one at a time. Each
/// attachment here is 2.5 chunks, so a whole one would show as a larger chunk.
@MainActor
@Suite("Backups stream attachments")
struct BackupStreamingTests {
    private static let size = BackupChunk.size * 5 / 2

    private typealias Fixture = StreamingFixture

    private func fixture() throws -> Fixture {
        try StreamingFixture(size: Self.size)
    }

    private func attachmentPath(_ id: UUID) -> String {
        "\(BackupFormat.attachmentsFolder)/\(id.uuidString)"
    }

    private func isAttachment(_ path: String) -> Bool {
        path.hasPrefix("attachments/")
    }

    @Test("Back Up Now streams each attachment in chunks, and the next one clones the unchanged files")
    func backUpNow() async throws {
        let fixture = try fixture()
        let first = try await fixture.harness.service.backUpNow()
        let reads = fixture.source.backupReads
        #expect(fixture.source.wholeLedgerReads == 0)
        #expect(reads.wholeReads == 0)
        #expect(reads.largestChunk <= BackupChunk.size)
        // Once to hash, once to write: never more than one chunk at a time.
        #expect(reads.streamedBytes == 2 * 2 * Self.size)
        #expect(fixture.storage.recorded.inMemoryWrites == 0)
        #expect(fixture.storage.recorded.writtenInMemory.last?.contains(where: isAttachment) == false)
        let stored = try fixture.storage.base.read(id: first.id)
        for attachment in fixture.attachments {
            #expect(stored[attachmentPath(attachment.id)] == attachment.data)
        }

        fixture.harness.advance(60)
        _ = try await fixture.harness.service.backUpNow()
        // Hashed only: both files are cloned from the first backup, not written from the bytes again.
        #expect(reads.streamedBytes == 3 * 2 * Self.size)
        #expect(fixture.storage.recorded.unchanged.last?.count == 2)
        #expect(fixture.storage.recorded.wholeFolderReads == 0)
    }

    @Test("A restore from the list hands each attachment to the store from its file, never in the snapshot")
    func restoreStored() async throws {
        let fixture = try fixture()
        let backup = try await fixture.harness.service.backUpNow()
        try fixture.source.base.deleteAttachment(id: fixture.attachments[0].id)
        fixture.harness.advance(60)

        _ = try await fixture.harness.service.restore(.stored(backup.id)) { _ in }

        #expect(fixture.source.wholeLedgerReads == 0)
        #expect(fixture.source.wholeLedgerReplaces == 0)
        #expect(fixture.source.restoredSnapshotBytes == [[0, 0]])
        #expect(fixture.source.restoredFromFiles == [true])
        #expect(fixture.source.restoreReads.wholeReads == 2)
        #expect(fixture.source.backupReads.wholeReads == 0)
        #expect(fixture.source.backupReads.largestChunk <= BackupChunk.size)
        #expect(fixture.storage.recorded.wholeFolderReads == 0)
        let restored = try fixture.source.base.ledgerSnapshot().attachments
        #expect(Set(restored.map(\.data)) == Set(fixture.attachments.map(\.data)))
    }

    @Test("A restore from a picked file streams attachments into a scratch folder, removed when it's done")
    func restorePicked() async throws {
        let fixture = try fixture()
        let backup = try await fixture.harness.service.backUpNow()
        let export = try await fixture.harness.service.exportBackup(id: backup.id)
        let file = fixture.storage.folder.deletingLastPathComponent()
            .appendingPathComponent("picked-\(UUID().uuidString).littleorbit-backup")
        try FileManager.default.copyItem(at: export.file, to: file)
        fixture.harness.service.discardExport(export)
        defer { try? FileManager.default.removeItem(at: file) }
        try fixture.source.base.deleteAttachment(id: fixture.attachments[1].id)
        fixture.harness.advance(60)

        _ = try await fixture.harness.service.restore(.file(at: file)) { _ in }

        // Only the manifest and the JSON files are read whole; attachments are only ever streamed.
        #expect(fixture.archiving.log.readWhole.contains(where: isAttachment) == false)
        #expect(fixture.archiving.log.readStreamed.contains(where: isAttachment))
        let scratches = fixture.storage.recorded.scratches
        #expect(scratches.count == 1)
        let scratch = try #require(scratches.first)
        #expect(Set(scratch.created) == Set(fixture.attachments.map { self.attachmentPath($0.id) }))
        #expect(scratch.largestChunk <= BackupChunk.size)
        #expect(scratch.wasRemoved)
        #expect(fixture.source.wholeLedgerReplaces == 0)
        #expect(fixture.source.restoredSnapshotBytes == [[0, 0]])
        #expect(fixture.source.restoredFromFiles == [true])
        #expect(fixture.source.restoreReads.wholeReads == 2)
        let restored = try fixture.source.base.ledgerSnapshot().attachments
        #expect(Set(restored.map(\.data)) == Set(fixture.attachments.map(\.data)))
    }

    @Test("A picked file whose check fails unpacks nothing")
    func failedCheckUnpacksNothing() async throws {
        let fixture = try fixture()
        let backup = try await fixture.harness.service.backUpNow()
        var files = try fixture.storage.base.read(id: backup.id)
        files[attachmentPath(fixture.attachments[0].id)] = Data(count: Self.size)
        let file = fixture.storage.folder.deletingLastPathComponent()
            .appendingPathComponent("picked-\(UUID().uuidString).littleorbit-backup")
        try fixture.archiving.archive(files).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        await #expect(throws: BackupError.damaged) {
            _ = try await fixture.harness.service.restore(.file(at: file)) { _ in }
        }
        #expect(fixture.source.restoredSnapshotBytes.isEmpty)
        #expect(fixture.storage.recorded.scratches.allSatisfy { $0.created.isEmpty && $0.wasRemoved })
    }
}
