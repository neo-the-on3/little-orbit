import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

/// Tech Architect B2: an export is written to a file of its own in the staging folder, each listed file streamed
/// from the backup folder in chunks and checked against the manifest on the way, and removed afterwards.
@MainActor
@Suite("Export writes a file")
struct BackupExportFileTests {
    private static let size = BackupChunk.size * 5 / 2

    @Test("Export streams the listed files, manifest first, into a file of its own that's removed afterwards")
    func streamsToFile() async throws {
        let fixture = try StreamingFixture(size: Self.size)
        let backup = try await fixture.harness.service.backUpNow()
        let export = try await fixture.harness.service.exportBackup(id: backup.id, named: "Mine.littleorbit-backup")

        #expect(export.record.id == backup.id)
        #expect(export.file.lastPathComponent == "Mine.littleorbit-backup")
        let folder = export.file.deletingLastPathComponent()
        #expect(folder.lastPathComponent.hasSuffix(".export"))
        #expect(
            folder.deletingLastPathComponent().standardizedFileURL.path
                == URL(fileURLWithPath: fixture.storage.folder.path + ".staging").standardizedFileURL.path
        )
        // Never the whole folder, and no file read whole: every chunk is at most 1 MB.
        #expect(fixture.storage.recorded.wholeFolderReads == 0)
        let written = fixture.archiving.written
        #expect(written.readWhole.isEmpty)
        #expect(written.largestChunk <= BackupChunk.size)
        let order = try #require(written.archived.last)
        #expect(order.first == BackupFormat.manifestPath)
        let stored = try fixture.storage.base.read(id: backup.id)
        #expect(Set(order) == Set(stored.paths))
        // The file is the backup: the same files, byte for byte.
        let entries = try fixture.archiving.entries(of: Data(contentsOf: export.file))
        #expect(try BackupArchiveSafety.files(from: entries) == stored)

        fixture.harness.service.discardExport(export)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(fixture.stagingIsEmpty)
    }

    @Test("A file that changed after the backup was checked fails the export, leaving no file, and is 'Damaged'")
    func changedFileFails() async throws {
        let fixture = try StreamingFixture(size: Self.size)
        let backup = try await fixture.harness.service.backUpNow()
        let url = fixture.backupFolder(backup.id)
            .appendingPathComponent(StreamingFixture.path(fixture.attachments[0].id))
        var bytes = try Data(contentsOf: url)
        bytes[bytes.count - 1] ^= 0xFF
        try bytes.write(to: url)

        await #expect(throws: BackupError.damaged) { try await fixture.harness.service.exportBackup(id: backup.id) }
        #expect(fixture.stagingIsEmpty)
        #expect(try await fixture.harness.service.overview().backups.first?.condition == .damaged)
    }

    @Test("A name that isn't one plain file name gets the backup's ID instead")
    func plainName() async throws {
        let fixture = try StreamingFixture(size: 10)
        let backup = try await fixture.harness.service.backUpNow()
        for name in ["../outside.littleorbit-backup", "a/b.littleorbit-backup", ".hidden", ""] {
            let export = try await fixture.harness.service.exportBackup(id: backup.id, named: name)
            #expect(export.file.lastPathComponent == "\(backup.id.uuidString).littleorbit-backup")
            fixture.harness.service.discardExport(export)
        }
        #expect(fixture.stagingIsEmpty)
    }

    @Test("An export left by an app that stopped is removed at the next launch")
    func sweptAtLaunch() async throws {
        let fixture = try StreamingFixture(size: 10)
        let backup = try await fixture.harness.service.backUpNow()
        let export = try await fixture.harness.service.exportBackup(id: backup.id)
        #expect(FileManager.default.fileExists(atPath: export.file.path))
        _ = try FileBackupStorage(folder: fixture.storage.folder)
        #expect(!FileManager.default.fileExists(atPath: export.file.path))
        #expect(fixture.stagingIsEmpty)
    }
}
