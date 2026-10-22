import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// Tester finding 3 on 4c8b0b3: the save panel's own copy of the export, which SwiftUI leaves in the app's `tmp`,
/// goes after `onCompletion` or `onCancellation` and at the next export, but never while another window's panel
/// may still be reading its copy.
@MainActor
@Suite("Export: the save panel's copy in tmp is removed")
struct BackupExportSystemCopyTests {
    private let manager = FileManager.default

    private struct Setup {
        let harness: BackupHarness
        let tmp: URL
        let backup: BackupRecord
        let model: BackupsViewModel
    }

    private func setUp() async throws -> Setup {
        let tmp = manager.temporaryDirectory.appendingPathComponent(
            "system-tmp-\(UUID().uuidString)",
            isDirectory: true,
        )
        try manager.createDirectory(at: tmp, withIntermediateDirectories: true)
        let folder = manager.temporaryDirectory.appendingPathComponent("backup-tests-\(UUID().uuidString)")
        let storage = try FileBackupStorage(folder: folder, systemTemporaryFolder: tmp)
        let harness = try BackupHarness(storage: storage)
        let backup = try await harness.service.backUpNow()
        return Setup(harness: harness, tmp: tmp, backup: backup, model: harness.viewModel())
    }

    /// What `fileExporter` does while its panel is up: a copy of the file, under its suggested name.
    private func panelCopy(_ setup: Setup, of window: BackupsWindow) throws -> URL {
        let export = try #require(window.pendingExport)
        let url = setup.tmp.appendingPathComponent(UUID().uuidString).appendingPathComponent(export.fileName)
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.copyItem(at: export.url, to: url)
        return url
    }

    private func export(_ window: BackupsWindow, _ id: UUID) async throws {
        await window.load()
        await window.requestExport(id)
        await window.export(try #require(window.exportPrompt))
        #expect(window.isExportPresented)
    }

    @Test("Cancel, then Save: each removes the panel's copy and its folder")
    func removedAfterEachCallback() async throws {
        let setup = try await setUp()
        defer { try? manager.removeItem(at: setup.tmp) }
        let window = BackupsWindow(model: setup.model)

        try await export(window, setup.backup.id)
        let cancelled = try panelCopy(setup, of: window)
        window.exportCancelled()
        #expect(!manager.fileExists(atPath: cancelled.path))
        #expect(!manager.fileExists(atPath: cancelled.deletingLastPathComponent().path))

        try await export(window, setup.backup.id)
        let saved = try panelCopy(setup, of: window)
        window.exportCompleted(.success(URL(fileURLWithPath: "/saved")))
        #expect(!manager.fileExists(atPath: saved.path))
    }

    @Test("A copy left by an earlier panel goes at the next export")
    func removedAtNextExport() async throws {
        let setup = try await setUp()
        defer { try? manager.removeItem(at: setup.tmp) }
        let left = setup.tmp.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("little-orbit 2026-10-05 1000.littleorbit-backup")
        try manager.createDirectory(at: left.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("copy".utf8).write(to: left)

        try await export(BackupsWindow(model: setup.model), setup.backup.id)
        #expect(!manager.fileExists(atPath: left.path))
    }

    @Test("Another window's panel still up: its copy stays until that panel closes")
    func otherPanelKeepsItsCopy() async throws {
        let setup = try await setUp()
        defer { try? manager.removeItem(at: setup.tmp) }
        let other = try await setup.harness.service.backUpNow()
        let first = BackupsWindow(model: setup.model)
        let second = BackupsWindow(model: setup.model)

        try await export(first, setup.backup.id)
        let firstCopy = try panelCopy(setup, of: first)
        try await export(second, other.id)
        #expect(manager.fileExists(atPath: firstCopy.path))
        _ = try panelCopy(setup, of: second)
        second.exportCancelled()
        #expect(manager.fileExists(atPath: firstCopy.path))

        first.exportCompleted(.success(URL(fileURLWithPath: "/saved")))
        #expect(try manager.contentsOfDirectory(atPath: setup.tmp.path).isEmpty)
    }
}
