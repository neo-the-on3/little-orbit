import Foundation
import LittleOrbitDomain
import Observation

/// One window's Backups UI state: its prompts, alerts, error, export file, restore toast and inline line, and its
/// 'Delete N Backups?' (Tech Architect: transient UI state is never on a shared model; the same as #87's B3
/// `AccountDeleteConfirmation`).
///
/// Each window root makes its own (iOS: the Settings sheet; macOS: the Settings window's Backups tab) and passes
/// it down. Whatever one window asks for shows only there, and confirming it there changes another window only
/// through the shared data: the list, and actions turning off while a backup or restore runs.
///
/// The prompts are settable so SwiftUI's presentation bindings can clear them. The confirm actions take the item
/// they presented, since SwiftUI clears the binding before the button's action runs (Tester B1, B2).
@MainActor
@Observable
public final class BackupsWindow {
    public var alert: BackupAlert?
    public var errorMessage: String?
    public var restorePrompt: BackupRestorePrompt?
    public var deletePrompt: BackupRowModel?
    public var exportPrompt: BackupExportPrompt?
    /// The file to hand to the save panel. It stays until the panel's `onCompletion` or `onCancellation` has run.
    public private(set) var pendingExport: BackupExportFile?
    /// Whether the save panel is up. Closing it only clears this; the file stays until a callback (B4).
    private var isShowingExportPanel = false
    /// 'Delete N Backups?' after this window lowered N or M (D195.5, L12).
    public var prunePrompt: BackupPrunePrompt?
    /// iOS: the toast "Backup restored · Before restore backup saved", after this window's restore.
    public var toast: String?
    /// macOS: the inline line in the Backups tab after this window's restore (frame 169:5253).
    public private(set) var restoredMessage: String?
    /// The progress screen's date and counts. Non-nil while this window's restore runs, so only this window shows
    /// the progress screen; the others just have their actions off.
    public private(set) var restoringSummary: String?

    @ObservationIgnored public let model: BackupsViewModel

    public init(model: BackupsViewModel) {
        self.model = model
    }

    /// The window closed: an export file neither callback removed goes with it (B4). The launch sweep covers an app
    /// that's killed.
    isolated deinit {
        if let pendingExport {
            model.discardExport(pendingExport)
        }
    }

    /// Whether this window shows the restore progress screen.
    public var isShowingRestoreProgress: Bool {
        restoringSummary != nil && model.restoreStep != nil
    }

    /// The N and M this window's steppers show: the proposed ones while its 'Delete N Backups?' waits, otherwise
    /// the saved ones.
    public var shownRetention: BackupRetention {
        prunePrompt?.plan.retention ?? model.retention
    }

    /// Off while a backup or restore runs anywhere, and while this window's 'Delete N Backups?' waits.
    public var retentionEnabled: Bool {
        model.retentionEnabled && prunePrompt == nil
    }

    public func load() async {
        await run { try await model.load() }
    }

    public func backUpNow() async {
        await run { try await model.backUpNow() }
    }

    // MARK: Delete

    public func requestDelete(_ id: UUID) {
        deletePrompt = model.deletePrompt(for: id)
    }

    public func confirmDelete(_ row: BackupRowModel) async {
        deletePrompt = nil
        await run { try await model.delete(row) }
    }

    public func cancelDelete() {
        deletePrompt = nil
    }

    // MARK: Keep

    public func proposeRetention(_ proposed: BackupRetention) async {
        await run { prunePrompt = try await model.proposeRetention(proposed) }
    }

    public func confirmPrune(_ prompt: BackupPrunePrompt) async {
        prunePrompt = nil
        await run { try await model.confirmPrune(prompt) }
    }

    /// Cancel, Esc or any other dismissal: the saved N and M show again (L13).
    public func cancelPrune() {
        prunePrompt = nil
    }

    // MARK: Export

    public func requestExport(_ id: UUID) async {
        exportPrompt = await model.exportPrompt(for: id)
    }

    public func export(_ prompt: BackupExportPrompt) async {
        exportPrompt = nil
        finishExport()
        await run {
            pendingExport = try await model.exportFile(prompt)
            isShowingExportPanel = true
        }
    }

    public func cancelExport() {
        exportPrompt = nil
    }

    /// Removes the export's file, if there is one (B2). Safe to call more than once.
    public func finishExport() {
        if let pendingExport {
            model.discardExport(pendingExport)
        }
        pendingExport = nil
        isShowingExportPanel = false
    }

    /// `fileExporter`'s `isPresented`. SwiftUI sets it to `false` when the save panel closes, before `onCompletion`
    /// on a save and with `onCancellation` on a cancel. Setting it only closes the panel: Apple doesn't say the bytes
    /// have reached the destination by then, and the panel's `FileWrapper` reads the file lazily, so the file stays
    /// until a callback (Tech Architect B4). iOS and macOS both export through `fileExporter`; there's no other
    /// share path.
    public var isExportPresented: Bool {
        get { isShowingExportPanel && pendingExport != nil }
        set {
            if !newValue {
                isShowingExportPanel = false
            }
        }
    }

    /// `fileExporter`'s `onCompletion`, after the operation. Saved or not, the file goes. If neither callback runs,
    /// the next export, the window closing, or the launch sweep removes it.
    public func exportCompleted(_ result: Result<URL, any Error>) {
        finishExport()
    }

    /// `fileExporter`'s `onCancellation`, after the panel was cancelled.
    public func exportCancelled() {
        finishExport()
    }

    // MARK: Restore

    public func requestRestore(_ id: UUID) async {
        await run { restorePrompt = try await model.restorePrompt(for: id) }
    }

    /// A picked file, checked where it is: nothing is copied or written (B1.1, D197a.1).
    public func restoreFromFile(_ archive: BackupArchiveSource) async {
        await run { restorePrompt = try await model.restorePrompt(forFile: archive) }
    }

    public func cancelRestore() {
        restorePrompt = nil
    }

    public func confirmRestore(_ prompt: BackupRestorePrompt) async {
        restorePrompt = nil
        guard model.actionsEnabled else {
            return
        }
        restoredMessage = nil
        restoringSummary = model.restoringSummary(for: prompt)
        defer { restoringSummary = nil }
        await run {
            if let outcome = try await model.restore(prompt) {
                toast = outcome.toast
                restoredMessage = outcome.restoredMessage
            }
        }
    }

    // MARK: Feedback

    public func dismissAlert() {
        alert = nil
    }

    public func dismissError() {
        errorMessage = nil
    }

    public func dismissToast() {
        toast = nil
    }

    private func run(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            switch BackupsViewModel.feedback(for: error) {
            case .alert(let shown):
                alert = shown
            case .error(let message):
                errorMessage = message
            case .none:
                break
            }
        }
    }
}
