import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

#if canImport(AppleArchive)
    /// The real exported file end to end: Apple Archive, SHA-256 and the folder store (L19, L20, L40).
    @MainActor
    @Suite("Backup service with Apple Archive")
    struct BackupAppleArchiveServiceTests {
        private func harness() throws -> BackupHarness {
            try BackupHarness(archiving: AppleArchiveBackupArchiving(), hashing: CryptoKitBackupHashing())
        }

        @Test("An export is one archive of the folder, and imports with the same balances (L19, L20)")
        func exportAndImport() async throws {
            let harness = try harness()
            let backup = try await harness.service.backUpNow()
            let export = try await harness.exportData(backup.id)
            let entries = try harness.archiving.entries(of: export)
            #expect(try BackupArchiveSafety.files(from: entries) == (try harness.storage.read(id: backup.id)))
            let mime = export.base64EncodedString(options: .lineLength76Characters)
            let received = try #require(Data(base64Encoded: mime, options: .ignoreUnknownCharacters))
            let hashing = CryptoKitBackupHashing()
            #expect(hashing.sha256Hex(received) == hashing.sha256Hex(export))
            #expect(
                try await harness.contents(.file(received))
                    == (try await harness.contents(.stored(backup.id)))
            )
        }

        @Test("The checked-in Newer DotDot Sample is what the helper makes (L40)")
        func sampleMatchesHelper() throws {
            let archiving = AppleArchiveBackupArchiving()
            let sample = try newerDotDotSample()
            let made = try makeNewerDotDotSample()
            if let output = ProcessInfo.processInfo.environment["LITTLE_ORBIT_WRITE_FIXTURES"], !output.isEmpty {
                try made.write(to: URL(fileURLWithPath: output).appendingPathComponent(newerDotDotSampleName))
            }
            #expect(sample == made)
            // Apple Archive won't read the `../outside.json` header itself; it's in the file, after the manifest.
            #expect(sample.range(of: Data("../outside.json".utf8)) != nil)
            let entries = try archiving.entries(of: sample)
            #expect(entries.first?.path == "manifest.json")
            #expect(entries.last == BackupArchiveEntry(path: "", kind: .other))
        }

        @Test("Importing the Newer DotDot Sample asks for an update and writes nothing anywhere (L40)")
        func newerDotDotImport() async throws {
            let harness = try harness()
            let backup = try await harness.service.backUpNow()
            let before = try harness.repository.ledgerSnapshot()
            let sample = try newerDotDotSample()
            await #expect(throws: BackupError.newerFormat) { try await harness.contents(.file(sample)) }

            let window = harness.window()
            let model = window.model
            try await model.load()
            await window.restoreFromFile(.data(sample))
            #expect(window.alert == .newerFormat)
            #expect(window.restorePrompt == nil)

            #expect(try harness.repository.ledgerSnapshot() == before)
            #expect(try harness.storedFiles() == [harness.backupFolder(backup.id).lastPathComponent])
            #expect(try await harness.service.overview().backups.map(\.id) == [backup.id])
            for folder in [
                harness.folder, harness.folder.deletingLastPathComponent(), FileManager.default.temporaryDirectory,
            ] {
                #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("outside.json").path))
            }
        }
    }

    let newerDotDotSampleName = "Newer DotDot Sample.littleorbit-backup"

    /// L40's test archive: a regular `manifest.json` at the root declaring format 2, a `shared.json`, and an entry
    /// `../outside.json`. Run the suite with `LITTLE_ORBIT_WRITE_FIXTURES=<Fixtures folder>` to write it again.
    func makeNewerDotDotSample() throws -> Data {
        let manifest = #"""
            {"backup":{"createdAt":"2026-10-22T03:42:05Z","kind":"manual","month":"2026-10","nameIndex":1},\#
            "format":"little-orbit-backup","formatVersion":2,"somethingNew":{"added":"in format 2"}}
            """#
        return try AppleArchiveBackupArchiving()
            .archive(
                BackupSnapshotFiles([
                    BackupFormat.manifestPath: Data(manifest.utf8),
                    BackupFormat.sharedPath: Data(#"{"accounts":[]}"#.utf8),
                    "../outside.json": Data(#"{"written":"outside the backup"}"#.utf8),
                ])
            )
    }

    func newerDotDotSample() throws -> Data {
        let url = try #require(
            Bundle.module.url(
                forResource: "Newer DotDot Sample",
                withExtension: "littleorbit-backup",
                subdirectory: "Fixtures",
            )
        )
        return try Data(contentsOf: url)
    }
#endif
