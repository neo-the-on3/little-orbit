import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

@testable import LittleOrbitPersistence

/// Tech Architect on 6455556 (B1), through the list: cleanup (Keep) never changes what a link in a backup folder
/// points at, and a symlink in the Backups folder is never a row. A Backups folder that can be listed but not
/// searched is Couldn’t Load Backups, never an empty list (D214.1).
@MainActor
@Suite("Backups and symlinks, through the list (B1)", .serialized, .timeLimit(.minutes(2)))
struct BackupSymlinkTests {
    private let outside = FileManager.default.temporaryDirectory
        .appendingPathComponent("symlink-outside-\(UUID().uuidString)", isDirectory: true)
    private let fileManager = FileManager.default

    private func cleanUp(_ harness: BackupHarness) {
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: harness.folder.path)
        for url in [outside, outside.appendingPathComponent("inner")] {
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        try? fileManager.removeItem(at: outside)
        try? fileManager.removeItem(at: harness.folder)
        try? fileManager.removeItem(at: URL(fileURLWithPath: harness.folder.path + ".staging"))
    }

    /// Three automatic backups a day apart, oldest first.
    private func threeBackups(_ harness: BackupHarness) async throws -> [BackupRecord] {
        for day in 0..<3 {
            harness.advance(86_400)
            try harness.repository.saveAccount(
                Account(name: "Day \(day)", type: .cash, currencyCode: "INR", openingBalance: 1, sortOrder: 10)
            )
            _ = try await harness.service.backUpAutomaticallyIfNeeded()
        }
        return try await harness.service.overview().backups.reversed()
    }

    /// A read-only folder outside the Backups folder, with a file and a read-only inner folder.
    private func readOnlyOutside() throws -> [String] {
        let inner = outside.appendingPathComponent("inner", isDirectory: true)
        try fileManager.createDirectory(at: inner, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: outside.appendingPathComponent("keep.txt"))
        try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: inner.path)
        try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: outside.path)
        return try state()
    }

    private func state() throws -> [String] {
        let inner = outside.appendingPathComponent("inner", isDirectory: true)
        return try [outside, inner]
            .map {
                String(
                    (try fileManager.attributesOfItem(atPath: $0.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0,
                    radix: 8,
                )
            } + [try fileManager.contentsOfDirectory(atPath: outside.path).sorted().joined(separator: ",")]
    }

    @Test("Keep deletes a backup holding a link to a read-only outside folder; the folder keeps its modes and files")
    func keepWithLinkInside() async throws {
        let harness = try BackupHarness()
        defer { cleanUp(harness) }
        let backups = try await threeBackups(harness)
        let before = try readOnlyOutside()
        let oldest = harness.backupFolder(backups[0].id)
        try fileManager.createSymbolicLink(at: oldest.appendingPathComponent("link"), withDestinationURL: outside)
        let window = harness.window()
        await window.load()

        await window.proposeRetention(BackupRetention(recentAutomatic: 1, monthlyMonths: 0))
        await window.confirmPrune(try #require(window.prunePrompt))

        #expect(window.alert == nil)
        #expect(try await harness.service.overview().backups.map(\.id) == [backups[2].id])
        #expect(!fileManager.fileExists(atPath: oldest.path))
        #expect(try state() == before)
    }

    @Test("A symlink in the Backups folder to a copy of a backup is never a row, and the list still loads")
    func linkIsNoRow() async throws {
        let harness = try BackupHarness()
        defer { cleanUp(harness) }
        let backups = try await threeBackups(harness)
        try fileManager.copyItem(at: harness.backupFolder(backups[0].id), to: outside)
        try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: outside.path)
        try fileManager.createSymbolicLink(
            at: harness.folder.appendingPathComponent("2026-10-30-09-00"),
            withDestinationURL: outside,
        )
        let relaunched = try BackupHarness(storage: FileBackupStorage(folder: harness.folder))
        let window = relaunched.window()

        await window.load()

        #expect(!window.model.isLoadFailed)
        #expect(try await relaunched.service.overview().backups.map(\.id) == backups.reversed().map(\.id))
    }

    @Test("A Backups folder that can be listed but not searched is Couldn’t Load Backups (D214.1)")
    func rootNotSearchable() async throws {
        let harness = try BackupHarness()
        defer { cleanUp(harness) }
        let backups = try await threeBackups(harness)
        let probe = harness.backupFolder(backups[0].id)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: harness.folder.path)
        guard (try? fileManager.attributesOfItem(atPath: probe.path)) == nil else {
            return  // Root can search it anyway.
        }
        let relaunched = try BackupHarness(storage: FileBackupStorage(folder: harness.folder))
        let window = relaunched.window()

        await window.load()

        #expect(window.model.isLoadFailed)
    }
}
