import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// Pass number `failingPass` of the archive reader throws `error`. Pass 3 is the restore's own pass, which unpacks
/// a picked file's attachments into a scratch folder.
private final class FailingPassArchiving: BackupArchiving, @unchecked Sendable {
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

/// The real restore's checks, with the restore itself failing as a Before restore backup that isn't restorable
/// does, once the progress screen is showing its first step.
/// A window whose restore fails, its fake restore, and a stored backup to restore.
@MainActor
private struct FailingWindow {
    let window: BackupsWindow
    let failing: FailingRestore
    let id: UUID

    var parts: (window: BackupsWindow, id: UUID) {
        (window, id)
    }
}

@MainActor
private final class FailingRestore: RestoreBackupUseCase {
    let base: any RestoreBackupUseCase
    let error: any Error
    /// Runs once the first step is reported, before the failure: the progress sheet appearing meanwhile.
    var onFirstStep: () -> Void = {}
    /// Fails only once the restore's task is cancelled, as when the window's request goes away.
    var waitsForCancellation = false

    init(base: any RestoreBackupUseCase, error: any Error) {
        self.base = base
        self.error = error
    }

    func checkBackup(_ source: BackupSource) async throws -> BackupManifest {
        try await base.checkBackup(source)
    }

    func restore(
        _ source: BackupSource,
        progress: @MainActor (BackupRestoreStep) -> Void,
    ) async throws -> BackupRecord {
        progress(.savingCurrentData)
        onFirstStep()
        if waitsForCancellation {
            try? await Task.sleep(for: .seconds(100))
        }
        throw error
    }
}

/// Tester F1 on d8cea30: an error from a restore after its confirmation was never shown, because the window set
/// its alert while the restore progress sheet was still up, and iOS won't present on a view that's already
/// presenting. The window now holds the error until what it presents has closed: the progress sheet's
/// `onDismiss`, or the confirmation's binding clearing (Tech Architect).
@MainActor
@Suite("A restore's error shows once the confirmation and progress have closed (Tester F1)", .timeLimit(.minutes(2)))
struct BackupRestoreFailureFeedbackTests {
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("picked-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func pickedFile() async throws -> URL {
        let source = try BackupHarness()
        let backup = try await source.service.backUpNow()
        let url = folder.appendingPathComponent("\(UUID().uuidString).littleorbit-backup")
        try await source.exportData(backup.id).write(to: url)
        return url
    }

    /// Confirms `prompt` as the alert's Restore button does: the binding is already cleared when the action runs.
    private func confirm(_ window: BackupsWindow, _ prompt: BackupRestorePrompt) async {
        window.restorePrompt = nil
        await window.confirmRestore(prompt)
    }

    /// The progress sheet, requested by the restore, appears late, after the restore has already failed. It closes
    /// as soon as it's up; nothing is presented until its `onDismiss`.
    private func expectHeldThroughLateSheet(_ window: BackupsWindow) {
        #expect(window.isShowingRestoreProgress)
        #expect(window.alert == nil)
        #expect(window.errorMessage == nil)
        window.restoreProgressAppeared()
        #expect(!window.isShowingRestoreProgress)
        #expect(window.alert == nil)
        #expect(window.errorMessage == nil)
        window.restoreProgressDismissed()
    }

    /// A window whose restore fails with `beforeRestoreFailed` after its first step, with a stored backup to restore.
    private func failingWindow(_ harness: BackupHarness) async throws -> FailingWindow {
        let backup = try await harness.service.backUpNow()
        var useCases = BackupUseCases(service: harness.service, authentication: AppLockOff())
        let failing = FailingRestore(base: useCases.restore, error: BackupError.beforeRestoreFailed)
        useCases.restore = failing
        let model = BackupsViewModel(
            useCases: useCases,
            presentation: BackupPresentation(
                locale: Locale(identifier: "en_US"),
                timeZone: harness.zone,
                device: .iPhone,
            ),
            now: { [clock = harness.clock] in clock.now },
        )
        let window = BackupsWindow(model: model)
        await window.load()
        return FailingWindow(window: window, failing: failing, id: backup.id)
    }

    @Test("Restore from File: a write error while unpacking shows Couldn’t Restore (D211.1) after the progress closes")
    func unpackWriteError() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try await pickedFile()
        let denied = CocoaError(.fileWriteNoPermission)
        let harness = try BackupHarness(archiving: FailingPassArchiving(failingPass: 3, error: denied))
        let window = harness.window()
        let ledger = try harness.repository.ledgerSnapshot()
        await window.restoreFromFile(.file(url))
        let prompt = try #require(window.restorePrompt)

        await confirm(window, prompt)
        expectHeldThroughLateSheet(window)
        #expect(window.alert == .restoreFailed)
        #expect(window.errorMessage == nil)
        // A write error isn't a read failure: not Couldn’t Open Backup.
        #expect(window.alert != .unreadableFile)
        #expect(try harness.repository.ledgerSnapshot() == ledger)
    }

    @Test("A failed Before restore backup shows Couldn’t Restore after the progress closes, stored or picked")
    func beforeRestoreFailed() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try await pickedFile()
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        var useCases = BackupUseCases(service: harness.service, authentication: AppLockOff())
        useCases.restore = FailingRestore(base: useCases.restore, error: BackupError.beforeRestoreFailed)
        let model = BackupsViewModel(
            useCases: useCases,
            presentation: BackupPresentation(
                locale: Locale(identifier: "en_US"),
                timeZone: harness.zone,
                device: .iPhone,
            ),
            now: { [clock = harness.clock] in clock.now },
        )
        let window = BackupsWindow(model: model)
        await window.load()

        await window.requestRestore(backup.id)
        await confirm(window, try #require(window.restorePrompt))
        expectHeldThroughLateSheet(window)
        #expect(window.alert == .beforeRestoreFailed)
        #expect(window.alert?.title == "Couldn’t Restore")
        window.dismissAlert()

        await window.restoreFromFile(.file(url))
        await confirm(window, try #require(window.restorePrompt))
        expectHeldThroughLateSheet(window)
        #expect(window.alert == .beforeRestoreFailed)
        #expect(window.errorMessage == nil)
    }

    @Test("An error that arrives while the confirmation is still showing is presented once it closes")
    func errorWhileConfirmationShows() async throws {
        let harness = try BackupHarness()
        let backup = try await harness.service.backUpNow()
        let gone = try await harness.service.backUpNow()
        let window = harness.window()
        await window.load()
        await window.requestRestore(backup.id)
        let showing = try #require(window.restorePrompt)
        try await harness.service.deleteBackup(id: gone.id)

        // Another request fails while "Restore This Backup?" is still up.
        await window.requestRestore(gone.id)
        #expect(window.restorePrompt == showing)
        #expect(window.alert == nil)

        // The alert's binding clears as it closes; only then is the error presented.
        window.restorePrompt = nil
        #expect(window.alert == .damaged)
    }

    @Test("With nothing else up, an error shows at once, as before")
    func nothingElseUp() async throws {
        let harness = try BackupHarness()
        let gone = try await harness.service.backUpNow()
        let window = harness.window()
        await window.load()
        try await harness.service.deleteBackup(id: gone.id)
        await window.requestRestore(gone.id)
        #expect(window.alert == .damaged)
    }

    @Test("A failure between the sheet's request and its onAppear waits for the sheet to appear and close")
    func failureBeforeOnAppear() async throws {
        let harness = try BackupHarness()
        let (window, id) = try await failingWindow(harness).parts
        await window.requestRestore(id)
        await confirm(window, try #require(window.restorePrompt))
        // Requested, not yet appeared: still presenting as far as the alert is concerned.
        #expect(window.isShowingRestoreProgress)
        #expect(window.alert == nil)
        window.restoreProgressAppeared()
        #expect(!window.isShowingRestoreProgress)
        #expect(window.alert == nil)
        window.restoreProgressDismissed()
        #expect(window.alert == .beforeRestoreFailed)
    }

    @Test("A failure while the sheet is up waits for its onDismiss")
    func failureWhileShown() async throws {
        let harness = try BackupHarness()
        let setup = try await failingWindow(harness)
        let (window, failing, id) = (setup.window, setup.failing, setup.id)
        failing.onFirstStep = { window.restoreProgressAppeared() }
        await window.requestRestore(id)
        await confirm(window, try #require(window.restorePrompt))
        #expect(!window.isShowingRestoreProgress)
        #expect(window.alert == nil)
        window.restoreProgressDismissed()
        #expect(window.alert == .beforeRestoreFailed)
    }

    @Test("Stuck case: the sheet's binding clears before onAppear, so the error shows then, once")
    func bindingClearsBeforeOnAppear() async throws {
        let harness = try BackupHarness()
        let (window, id) = try await failingWindow(harness).parts
        await window.requestRestore(id)
        await confirm(window, try #require(window.restorePrompt))
        #expect(window.alert == nil)
        window.restoreProgressBindingCleared()
        #expect(!window.isShowingRestoreProgress)
        #expect(window.alert == .beforeRestoreFailed)
        window.dismissAlert()
        // A late callback changes nothing.
        window.restoreProgressAppeared()
        window.restoreProgressDismissed()
        #expect(window.alert == nil)
        #expect(!window.isShowingRestoreProgress)
    }

    @Test("Stuck case: a cancelled request before onAppear shows the error once nothing is presenting")
    func cancelledBeforeOnAppear() async throws {
        let harness = try BackupHarness()
        let setup = try await failingWindow(harness)
        let (window, failing, id) = (setup.window, setup.failing, setup.id)
        failing.waitsForCancellation = true
        await window.requestRestore(id)
        let prompt = try #require(window.restorePrompt)
        window.restorePrompt = nil
        let task = Task { await window.confirmRestore(prompt) }
        await pollOnMainQueue { window.isShowingRestoreProgress }
        #expect(window.isShowingRestoreProgress)
        task.cancel()
        await task.value
        #expect(!window.isShowingRestoreProgress)
        #expect(window.alert == .beforeRestoreFailed)
    }

    @Test("Stuck case: a window that closes with an error still held lets it go with the window")
    func windowClosesWithHeldError() async throws {
        let harness = try BackupHarness()
        let (window, id) = try await failingWindow(harness).parts
        var held: BackupsWindow? = BackupsWindow(model: window.model)
        weak let released = held
        await held?.requestRestore(id)
        if let held, let prompt = held.restorePrompt {
            await confirm(held, prompt)
            #expect(held.alert == nil)
            #expect(held.isShowingRestoreProgress)
        }
        held = nil
        await pollOnMainQueue { released == nil }
        #expect(released == nil)
    }
}
