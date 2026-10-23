import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// UI Designer on 7bc7cad: when the list couldn't load, Keep showed the defaults, 7 and 12, and raising a stepper
/// then saved over the user's N and M. They're read from the settings, which don't need the Backups folder.
@MainActor
@Suite("Keep shows the saved N and M when the list can't load (D211.5)", .timeLimit(.minutes(2)))
struct BackupLoadFailedKeepTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("keep-\(UUID().uuidString)")

    private func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: folder.path + ".staging"))
    }

    private static let saved = BackupRetention(recentAutomatic: 3, monthlyMonths: 6)

    /// A window over a new view model, whose first load fails, with `saved` as the stored N and M.
    private func failedWindow() async throws -> (BackupHarness, BackupsWindow) {
        let storage = try ScriptedStorage(folder: folder)
        let harness = try BackupHarness(storage: storage)
        harness.settings.setRetention(Self.saved)
        storage.listError = CocoaError(.fileReadNoPermission)
        let window = harness.window()
        await window.load()
        #expect(window.model.isLoadFailed)
        return (harness, window)
    }

    @Test("A failed first load still shows the saved N and M, in the steppers and the footer")
    func showsSaved() async throws {
        defer { cleanUp() }
        let (harness, window) = try await failedWindow()
        #expect(window.shownRetention == Self.saved)
        #expect(window.model.presentation.retention == Self.saved)
        #expect(window.model.retention == Self.saved)
        let healthy = try BackupHarness()
        healthy.settings.setRetention(Self.saved)
        let loaded = healthy.window()
        await loaded.load()
        #expect(window.model.keepFooter == loaded.model.keepFooter)
        #expect(harness.settings.retention() == Self.saved)
    }

    @Test("Raising a stepper after a failed load saves one more than the saved value, not over it with a default")
    func raisingKeepsSaved() async throws {
        defer { cleanUp() }
        let (harness, window) = try await failedWindow()
        await window.proposeRetention(BackupRetention(recentAutomatic: 4, monthlyMonths: 6))
        #expect(harness.settings.retention() == BackupRetention(recentAutomatic: 4, monthlyMonths: 6))
        #expect(window.prunePrompt == nil)
        #expect(window.alert == nil)
        await window.proposeRetention(BackupRetention(recentAutomatic: 4, monthlyMonths: 7))
        #expect(harness.settings.retention() == BackupRetention(recentAutomatic: 4, monthlyMonths: 7))
        #expect(window.shownRetention == BackupRetention(recentAutomatic: 4, monthlyMonths: 7))
    }
}
