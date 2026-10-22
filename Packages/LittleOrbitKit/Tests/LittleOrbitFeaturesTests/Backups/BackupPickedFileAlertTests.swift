import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// The fake archive reader, with pass number `failingPass` throwing `error`, as a file evicted mid-read would.
private final class FailingFakeArchiving: BackupArchiving, @unchecked Sendable {
    private let base = FakeBackupArchiving()
    private let failingPass: Int
    private let error: any Error
    private var passes = 0

    init(failingPass: Int, error: any Error) {
        self.failingPass = failingPass
        self.error = error
    }

    func archive(_ files: BackupSnapshotFiles) throws -> Data {
        try base.archive(files)
    }

    func entries(
        of archive: BackupArchiveSource,
        reading: (String) -> BackupArchiveRead,
    ) throws -> [BackupArchiveEntry] {
        passes += 1
        if passes == failingPass {
            throw error
        }
        return try base.entries(of: archive, reading: reading)
    }
}

private struct UnexpectedReaderError: LocalizedError {
    var errorDescription: String? { "Unexpected" }
}

/// Which alert a picked file gets (D207.2): one that can't be read at all is 'Couldn’t Open Backup'; one that's read
/// but fails the manifest, safety or checksum checks is 'This Backup Is Damaged' (D195a, D196); a newer format is
/// D197's update alert. Each leaves the data unchanged, and none is the generic error alert.
@MainActor
@Suite("Picked file alerts (D207.2)", .timeLimit(.minutes(2)))
struct BackupPickedFileAlertTests {
    private let harness: BackupHarness
    private let folder: URL

    init() throws {
        harness = try BackupHarness()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("picked-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func picked(_ data: Data) throws -> URL {
        let url = folder.appendingPathComponent("\(UUID().uuidString).littleorbit-backup")
        try data.write(to: url)
        return url
    }

    /// Restores `url` in a new window and returns its alert, checking the data and the list didn't change.
    private func alert(for url: URL) async throws -> BackupAlert? {
        defer { try? FileManager.default.removeItem(at: folder) }
        let window = harness.window()
        try await window.model.load()
        let ledger = try harness.repository.ledgerSnapshot()
        let rows = window.model.rows.count
        await window.restoreFromFile(.file(url))
        #expect(window.errorMessage == nil)
        #expect(window.restorePrompt == nil)
        #expect(try harness.repository.ledgerSnapshot() == ledger)
        #expect(window.model.rows.count == rows)
        #expect(harness.changes.replacements == 0)
        return window.alert
    }

    /// A good export of a new backup, as its entries.
    private func exportedEntries() async throws -> [BackupArchiveEntry] {
        let backup = try await harness.service.backUpNow()
        let exported = try await harness.exportData(backup.id)
        return try FakeBackupArchiving().entries(of: .data(exported)) { _ in .data }
    }

    @Test("A file that isn't there, like an iCloud placeholder that isn't downloaded, can't be opened")
    func missing() async throws {
        let shown = try await alert(for: folder.appendingPathComponent("not-downloaded.littleorbit-backup"))
        #expect(shown == .unreadableFile)
        #expect(shown?.title == "Couldn’t Open Backup")
        #expect(
            shown?.message
                == "The file couldn’t be read. Make sure it’s fully downloaded and try again. Your data hasn’t changed."
        )
    }

    @Test("A file without read permission can't be opened", .enabled(if: getuid() != 0))
    func noPermission() async throws {
        let url = try picked(Data("anything".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        #expect(try await alert(for: url) == .unreadableFile)
    }

    @Test("A folder picked as a file can't be opened")
    func folderAsFile() async throws {
        let url = folder.appendingPathComponent("folder.littleorbit-backup")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #expect(try await alert(for: url) == .unreadableFile)
    }

    @Test("A file that's read but isn't a backup is damaged", arguments: [Data(), Data("Shopping list".utf8)])
    func notABackup(data: Data) async throws {
        #expect(try await alert(for: picked(data)) == .damaged)
    }

    @Test("A file with no manifest is damaged")
    func noManifest() async throws {
        let entries = try await exportedEntries().filter { $0.path != "manifest.json" }
        #expect(try await alert(for: picked(FakeBackupArchiving.crafted(entries))) == .damaged)
    }

    @Test("A file with an unsafe entry is damaged")
    func unsafeEntry() async throws {
        var entries = try await exportedEntries()
        entries.append(BackupArchiveEntry(path: "../escape.json", kind: .file(Data("{}".utf8))))
        #expect(try await alert(for: picked(FakeBackupArchiving.crafted(entries))) == .damaged)
    }

    @Test("A file whose bytes don't match their checksum is damaged")
    func checksum() async throws {
        let entries = try await exportedEntries()
            .map { entry in
                guard entry.path == "shared.json", case .file(var data?) = entry.kind else {
                    return entry
                }
                data[data.startIndex] ^= 1
                return BackupArchiveEntry(path: entry.path, kind: .file(data))
            }
        #expect(try await alert(for: picked(FakeBackupArchiving.crafted(entries))) == .damaged)
    }

    @Test("A newer format keeps the update alert")
    func newerFormat() async throws {
        let entries = try await exportedEntries()
            .map { entry in
                guard entry.path == "manifest.json", case .file(let data?) = entry.kind,
                    var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    return entry
                }
                object["formatVersion"] = BackupFormat.currentVersion + 1
                let newer = (try? JSONSerialization.data(withJSONObject: object)) ?? data
                return BackupArchiveEntry(path: entry.path, kind: .file(newer))
            }
        #expect(try await alert(for: picked(FakeBackupArchiving.crafted(entries))) == .newerFormat)
    }

    /// A good backup file, then a window restoring it through a reader whose `pass` fails with `error`.
    private func restoring(failingPass pass: Int, error: any Error) async throws -> BackupsWindow {
        let backup = try await harness.service.backUpNow()
        let url = try picked(try await harness.exportData(backup.id))
        defer { try? FileManager.default.removeItem(at: url) }
        let failing = try BackupHarness(archiving: FailingFakeArchiving(failingPass: pass, error: error))
        let window = failing.window()
        let ledger = try failing.repository.ledgerSnapshot()
        await window.restoreFromFile(.file(url))
        #expect(window.restorePrompt == nil)
        #expect(try failing.repository.ledgerSnapshot() == ledger)
        return window
    }

    @Test("A read error partway through, like iCloud evicting the file mid-read, is Couldn’t Open Backup")
    func readErrorMidStream() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        for error: any Error in [
            CocoaError(.fileReadUnknown), POSIXError(.EIO), CocoaError(.ubiquitousFileUnavailable),
        ] {
            let window = try await restoring(failingPass: 2, error: error)
            #expect(window.alert == .unreadableFile)
            #expect(window.errorMessage == nil)
        }
    }

    @Test("A truly unexpected error keeps Something Went Wrong")
    func unexpectedError() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let window = try await restoring(failingPass: 2, error: UnexpectedReaderError())
        #expect(window.alert == nil)
        #expect(window.errorMessage == "Unexpected")
    }

    @Test("Each case maps to its own alert, and only a picked file's read failure is Couldn’t Open Backup")
    func feedback() {
        #expect(BackupsViewModel.feedback(for: BackupError.unreadableFile) == .alert(.unreadableFile))
        #expect(BackupsViewModel.feedback(for: BackupError.damaged) == .alert(.damaged))
        #expect(BackupsViewModel.feedback(for: BackupError.newerFormat) == .alert(.newerFormat))
        #expect(BackupsViewModel.feedback(for: BackupError.beforeRestoreFailed) == .alert(.beforeRestoreFailed))
    }
}
