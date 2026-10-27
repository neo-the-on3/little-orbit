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

extension WindowUndoHistory {
    /// From a failure until its alert is dismissed, or while a batch runs in any window: Undo and Redo are off.
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
        let progress = BatchProgress(kind: undoing ? .undoing : .redoing, total: step.change.transactionIDs.count)
        batchProgress = progress
        let reporter = progress.start()
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
                result = .success(try await changes.revert(change, expecting: outcome, reporting: reporter))
            } catch {
                result = .failure(error)
            }
            guard let self else {
                // The history went without `cancelBatch`: the batch still ends, so writes come back on.
                progress.finish()
                updates.endBatch()
                return
            }
            self.finishBatch(step, undoing: undoing, title: shown, result: result)
        }
        batchRun = (task, step)
    }

    /// Stops a batch Undo or Redo that hasn't written yet: nothing is written and its step goes, without an alert.
    /// The window calls it when it closes; clearing the history does too.
    public func cancelBatch() {
        guard let run = batchRun else {
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
    ) {
        guard let run = batchRun, run.step === step else {
            // Cancelled: `cancelBatch` already removed the step.
            return
        }
        batchRun = nil
        endBatch()
        switch result {
        case .success(.reverted(let inverse, let outcome)):
            step.change = inverse
            step.outcome = outcome
            notice = noticeAfterApplying(step)
            announce(undoing ? UndoText.undid(shown) : UndoText.redid(shown))
            updates.changed()
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

    private func endBatch() {
        batchProgress?.finish()
        batchProgress = nil
        updates.endBatch()
    }

    /// Outside an Undo or Redo, removing a step's actions leaves no empty group on the `UndoManager`. A stand-in
    /// still holding the step, from an Undo or Redo swallowed while it ran, is dropped too, so it can't put the
    /// step back afterwards.
    private func removeInFlight(_ step: Step) {
        undoSteps.removeAll { $0 === step }
        redoSteps.removeAll { $0 === step }
        registrar?.removeSteps(for: step)
        for standIn in failure.standIns where standIn.step === step && !standIn.hasRun {
            standIn.isDropped = true
        }
    }
}
