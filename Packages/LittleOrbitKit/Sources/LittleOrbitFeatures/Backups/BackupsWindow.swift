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
    /// "Restore This Backup?". An error that arrives while it's up waits until its binding clears (Tester F1).
    public var restorePrompt: BackupRestorePrompt? {
        didSet {
            if restorePrompt == nil {
                showHeldFeedback()
            }
        }
    }
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

    /// Where this window's restore progress sheet is, from the restore asking for it until its `onDismiss`.
    private var progress = RestoreProgress.none
    /// An alert or error that came while this window was presenting something else: its restore confirmation or its
    /// progress sheet. iOS refuses to present an alert on a view that's already presenting, and SwiftUI doesn't try
    /// again, so the error would never show (Tester F1). It's set as the window's alert or error once those have
    /// closed: the confirmation's binding cleared, the progress sheet's `onDismiss` run.
    @ObservationIgnored private var heldFeedback: BackupFeedback?

    @ObservationIgnored public let model: BackupsViewModel
    /// The shared ledger signal: while a Bulk Edit, or its Undo or Redo, runs in any window, Restore waits (D399).
    @ObservationIgnored private let ledgerUpdates: LedgerUpdates?

    public init(model: BackupsViewModel, ledgerUpdates: LedgerUpdates? = nil) {
        self.model = model
        self.ledgerUpdates = ledgerUpdates
    }

    /// Restore… and Restore from File…: off while a backup or restore runs (D118.5) or a batch runs in any window
    /// (D399). Back Up Now, Export… and Delete… don't write the ledger, so they don't wait for a batch.
    public var restoreEnabled: Bool {
        model.actionsEnabled && !(ledgerUpdates?.isBatchRunning ?? false)
    }

    /// The window closed: an export file neither callback removed goes with it (B4), and so does an error still held
    /// for a progress sheet that never appeared. The launch sweep covers an app that's killed.
    isolated deinit {
        if let pendingExport {
            model.discardExport(pendingExport)
        }
    }

    /// Whether this window shows the restore progress screen: the sheet's `isPresented`. It stays on after a restore
    /// that ended before the sheet appeared, so the sheet appears and then closes, and an error waits for its
    /// `onDismiss`.
    public var isShowingRestoreProgress: Bool {
        switch progress {
        case .requested, .shown:
            true
        case .none, .closing:
            false
        }
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
        guard restoreEnabled else { return }
        await run { restorePrompt = try await model.restorePrompt(for: id) }
    }

    /// A picked file, checked where it is: nothing is copied or written (B1.1, D197a.1).
    public func restoreFromFile(_ archive: BackupArchiveSource) async {
        guard restoreEnabled else { return }
        await run { restorePrompt = try await model.restorePrompt(forFile: archive) }
    }

    public func cancelRestore() {
        restorePrompt = nil
    }

    public func confirmRestore(_ prompt: BackupRestorePrompt) async {
        restorePrompt = nil
        guard restoreEnabled else {
            return
        }
        restoredMessage = nil
        restoringSummary = model.restoringSummary(for: prompt)
        progress = .requested(finished: false, unbound: false)
        await run {
            if let outcome = try await model.restore(prompt) {
                toast = outcome.toast
                restoredMessage = outcome.restoredMessage
            }
        }
        // An error from the restore was held. It shows after the sheet's `onDismiss`, even when the sheet appears
        // only now. If the sheet can't appear any more, it shows at once.
        switch progress {
        case .shown:
            progress = .closing
        case .requested(_, let unbound):
            if unbound || Task.isCancelled {
                endProgress()
            } else {
                progress = .requested(finished: true, unbound: false)
            }
        case .none, .closing:
            endProgress()
        }
    }

    /// The restore progress sheet's content appeared. A restore that already ended closes it again at once.
    public func restoreProgressAppeared() {
        if case .requested(let finished, _) = progress {
            progress = finished ? .closing : .shown
        }
    }

    /// The progress sheet's `isPresented` went false. Before the sheet appeared, it may never appear now: a held
    /// error shows at once if the restore has ended, or when it ends. Once the sheet is up, `onDismiss` follows.
    public func restoreProgressBindingCleared() {
        if case .requested(let finished, _) = progress {
            if finished {
                endProgress()
            } else {
                progress = .requested(finished: false, unbound: true)
            }
        }
    }

    /// The restore progress sheet's `onDismiss`: it has fully closed, so a held error can be presented.
    public func restoreProgressDismissed() {
        switch progress {
        case .shown, .closing:
            endProgress()
        case .none, .requested:
            break
        }
    }

    /// Nothing of the restore is presented any more: a held error shows now.
    private func endProgress() {
        progress = .none
        restoringSummary = nil
        showHeldFeedback()
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
            show(BackupsViewModel.feedback(for: error))
        }
    }

    /// Whether this window is presenting its restore confirmation or progress, so an alert can't go up yet.
    private var isPresentingRestore: Bool {
        restorePrompt != nil || progress != .none
    }

    /// `feedback` as this window's alert or error, or held until its restore confirmation and progress have closed.
    private func show(_ feedback: BackupFeedback) {
        guard !isPresentingRestore else {
            heldFeedback = feedback
            return
        }
        switch feedback {
        case .alert(let shown):
            alert = shown
        case .error(let message):
            errorMessage = message
        case .none:
            break
        }
    }

    private func showHeldFeedback() {
        guard let held = heldFeedback, !isPresentingRestore else {
            return
        }
        heldFeedback = nil
        show(held)
    }
}

/// The restore progress sheet, from the restore asking for it until its `onDismiss` (Tester F1, Tech Architect). From
/// the request until the sheet's `onAppear` it counts as presenting, as an alert set then would be refused too.
private enum RestoreProgress: Equatable {
    case none
    /// The restore asked for the sheet and it hasn't appeared yet. `finished`: the restore has ended, so the sheet
    /// closes as soon as it appears. `unbound`: the sheet's binding cleared, so it may never appear.
    case requested(finished: Bool, unbound: Bool)
    /// The sheet is up and the restore runs.
    case shown
    /// The restore has ended and the sheet is closing; its `onDismiss` hasn't run yet.
    case closing
}
