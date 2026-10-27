import Foundation
import LittleOrbitCore
import LittleOrbitDomain

// MARK: The Undo and Redo of a Bulk Edit (#285, D398)
//
// The step is registered again at once, while the `UndoManager` is still undoing or redoing, so it lands on the
// other list as any step does; the reverted rows are then built off the main actor, with progress, and written in
// one change. Until that ends, Undo and Redo are off in this window and every ledger write is off in every window;
// a command given meanwhile applies nothing. If the revert fails, is stale or is cancelled (the window closed or
// its history was cleared), nothing is written and the registered step is removed, so no half-done step is left.
// A revert already handed off to a background save (#285, B) can't be cancelled: cancelling it lets the save end,
// with busy held until then, and the change it wrote is still posted to every window (B1). A revert that wrote ends
// in `WindowUndoHistory+BatchEnd.swift`: its sheet closes first, then the windows refresh, then the batch ends.

extension WindowUndoHistory {
    /// The batch Undo or Redo running in this window.
    struct BatchRun {
        let task: Task<Void, Never>
        let step: Step
        /// Set once the revert is handed off to a background save (`LedgerBatchReporter.handingOff`), or once it has
        /// written: from then on it writes whatever `cancelBatch` does.
        var isHandedOff = false
        /// `cancelBatch` ran after the hand-off: the run ends when the save does, without a step, alert or notice.
        var isDetached = false
    }

    /// From a failure until its alert is dismissed, or while a batch runs in any window: Undo and Redo are off.
    /// During a batch the Mac's Edit › Undo and Redo are off too (`UndoCommandGate`, D407.1); anything that still
    /// reaches `run`, such as the window's `UndoManager` driven directly, applies nothing (D399).
    var isBusy: Bool { failure.isBlocked || updates.isBatchRunning }

    /// A Bulk Edit, or its Undo or Redo, is running in some window: ledger writes are off in every window.
    public var isBatchRunning: Bool { updates.isBatchRunning }

    /// Marks the step just recorded for `change`, a Bulk Edit, so its Undo and Redo run as a batch.
    public func markBulkEdit(_ change: TransactionChange) {
        if let step = undoSteps.last, step.change == change {
            step.runsInBatch = true
        }
    }

    func runInBatch(_ step: Step, undoing: Bool, title shown: String) {
        guard updates.beginBatch() else {
            swallow(step, undoing: undoing, title: shown)
            return
        }
        // Where it lands if the revert succeeds; removed again if it doesn't.
        if undoing {
            redoSteps.append(step)
        } else {
            undoSteps.append(step)
        }
        register(step, as: step.name)
        alert = nil
        let progress = BatchProgress(
            kind: undoing ? .undoing : .redoing,
            total: step.change.transactionIDs.count,
            showAfter: progressShowDelay,
            now: progressClock,
        )
        batchProgress = progress
        var reporter = progress.start()
        let stepID = ObjectIdentifier(step)
        let progressHandingOff = reporter.handingOff
        reporter.handingOff = { [weak self] in
            progressHandingOff()
            self?.batchHandedOff(stepID)
        }
        // Saved off the main actor: the sheet goes before the result is installed (D405 on 3dc318b).
        reporter.willInstall = { [weak self] in await self?.closeSheetBeforeInstall(stepID) }
        let changes = changes
        let change = step.change
        let outcome = step.outcome
        let updates = updates
        refreshMenu()
        let task = Task { [weak self] in
            let span = BatchTrace.begin(undoing ? "batch.undo" : "batch.redo")
            defer { span.end() }
            let result: Result<RevertResult, any Error>
            do {
                // The phase first: the UI draws Undoing or Redoing before any work starts (N5).
                await BatchProgress.uiTurn()
                result = .success(try await changes.revert(change, expecting: outcome, reporting: reporter))
            } catch {
                result = .failure(error)
            }
            guard let self else {
                // The history went without `cancelBatch` (NB3): nothing is left to announce to, and nothing of the
                // window's is reached. A revert handed off before it went has written: every other window still hears
                // of it once (B1), and the batch ends once they've refreshed, as every batch does (D403.1). Once the
                // revert has returned to a history still here, `finishBatch` holds it to the end, the announcement
                // included (Tech Architect on 0d676f8: no unowned in the batch's end).
                progress.finish()
                if case .success(.reverted(let inverse, _)) = result {
                    step.change = inverse
                    updates.changed(Self.delta(of: step))
                    await updates.settle()
                }
                updates.endBatch()
                return
            }
            await self.finishBatch(step, undoing: undoing, title: shown, result: result)
        }
        batchRun = BatchRun(task: task, step: step)
    }

    /// Stops a batch Undo or Redo that hasn't been handed off to its save yet: nothing is written, busy ends now and
    /// its step goes, without an alert. Once handed off to a background save it can't be stopped (B1): busy stays
    /// on and the run is only detached from this window, so when the save ends its step goes without an alert, notice
    /// or announcement and, if it wrote, every window hears of the change once; the batch ends once they've refreshed.
    /// A revert that has written can't be stopped either. The window calls it when it closes; clearing the history
    /// does too.
    public func cancelBatch() {
        guard let run = batchRun else {
            return
        }
        guard !run.isHandedOff else {
            batchRun?.isDetached = true
            BatchTrace.event("batch.cancel.deferred")
            // A revert that wrote and waits for its sheet to go stops waiting: its window is going.
            closingProgress?.sheetClosed()
            return
        }
        run.task.cancel()
        batchRun = nil
        endBatch()
        removeInFlight(run.step)
        refreshMenu()
    }

    private func finishBatch(
        _ step: Step,
        undoing: Bool,
        title shown: String,
        result: Result<RevertResult, any Error>,
    ) async {
        guard let run = batchRun, run.step === step else {
            // Cancelled: `cancelBatch` already removed the step.
            return
        }
        if case .success(.reverted(let inverse, let outcome)) = result {
            step.change = inverse
            step.outcome = outcome
            // The sheet closes, the windows refresh, then the batch ends (D403.1, D405).
            await finishReverted(step, undoing: undoing, title: shown)
            return
        }
        batchRun = nil
        endBatch()
        guard !run.isDetached else {
            // Nothing was written: the step goes, with no alert (B1).
            removeInFlight(step)
            refreshMenu()
            return
        }
        switch result {
        case .success(.reverted):
            // Handled above.
            break
        case .success(.stale(let reason)):
            // Nothing was written, and the step goes (D187.5).
            removeInFlight(step)
            alert = UndoAlert(
                title: undoing ? StaleText.cantUndo(shown) : StaleText.cantRedo(shown),
                message: staleMessage(reason, step),
            )
        case .failure(is CancellationError):
            removeInFlight(step)
        case .failure(let error):
            // Nothing was written; the step is removed, and the alert says so (D398).
            removeInFlight(step)
            alert = UndoAlert(
                title: Self.failedTitle(undoing: undoing, shown),
                message: AccountHistoryViewModel.message(for: error) + "\n" + UndoText.removedFromHistory,
            )
        }
        refreshMenu()
    }

    /// The revert is about to be handed off to a background save: from now on `cancelBatch` can't stop it (B1).
    private func batchHandedOff(_ stepID: ObjectIdentifier) {
        guard let run = batchRun, ObjectIdentifier(run.step) == stepID else {
            return
        }
        batchRun?.isHandedOff = true
    }

    /// The progress sheet's `onDismiss` ran. On macOS that can be as its dismissal starts, so the announcement held
    /// for it waits for the main actor's next free turn and the end of the dismissal (`BatchProgress.sheetDismissed`).
    /// The ended batch's progress stays drawn until then.
    public func batchSheetDismissed() {
        closingProgress?.sheetDismissed()
    }

    private func endBatch() {
        batchProgress?.finish()
        batchProgress = nil
        updates.endBatch()
    }

    /// Outside an Undo or Redo, removing a step's actions leaves no empty group on the `UndoManager`. A stand-in
    /// still holding the step, from an Undo or Redo swallowed while it ran, is dropped too, so it can't put the
    /// step back afterwards.
    func removeInFlight(_ step: Step) {
        undoSteps.removeAll { $0 === step }
        redoSteps.removeAll { $0 === step }
        registrar?.removeSteps(for: step)
        for standIn in failure.standIns where standIn.step === step && !standIn.hasRun {
            standIn.isDropped = true
        }
    }
}
