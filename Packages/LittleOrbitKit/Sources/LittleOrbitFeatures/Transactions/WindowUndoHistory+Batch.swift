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
// with busy held until then, and the change it wrote is still posted to every window (B1).

extension WindowUndoHistory {
    /// The batch Undo or Redo running in this window.
    struct BatchRun {
        let task: Task<Void, Never>
        let step: Step
        /// Set once the revert is handed off to a background save (`LedgerBatchReporter.handingOff`): from then on
        /// it writes whatever `cancelBatch` does.
        var isHandedOff = false
        /// `cancelBatch` ran after the hand-off: the run ends when the save does, without a step, alert or notice.
        var isDetached = false
    }

    /// From a failure until its alert is dismissed, or while a batch runs in any window: Undo and Redo are off.
    /// The system Edit menu validates against the window's `UndoManager`, which still holds the steps, so a menu
    /// opened before the batch can show them enabled; choosing one reaches `run`, which applies nothing (D399).
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
        reporter.handingOff = { [weak self] in self?.batchHandedOff(stepID) }
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
                // The history went without `cancelBatch`: the batch still ends, so writes come back on. A revert
                // handed off before it went has written: every other window still hears of it (B1).
                progress.finish()
                updates.endBatch()
                if case .success(.reverted(let inverse, _)) = result {
                    step.change = inverse
                    updates.changed(Self.delta(of: step))
                }
                return
            }
            self.finishBatch(step, undoing: undoing, title: shown, result: result)
        }
        batchRun = BatchRun(task: task, step: step)
    }

    /// Stops a batch Undo or Redo that hasn't been handed off to its save yet: nothing is written, busy ends now and
    /// its step goes, without an alert. Once handed off to a background save it can't be stopped (B1): busy stays
    /// on and the run is only detached from this window, so when the save ends the batch ends, its step goes
    /// without an alert, notice or announcement, and, if it wrote, every window hears of the change once. The
    /// window calls it when it closes; clearing the history does too.
    public func cancelBatch() {
        guard let run = batchRun else {
            return
        }
        guard !run.isHandedOff else {
            batchRun?.isDetached = true
            BatchTrace.event("batch.cancel.deferred")
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
        let progress = batchProgress
        endBatch()
        guard !run.isDetached else {
            finishDetached(step, result: result)
            return
        }
        switch result {
        case .success(.reverted(let inverse, let outcome)):
            step.change = inverse
            step.outcome = outcome
            notice = noticeAfterApplying(step)
            // Once the sheet has closed if it showed, now if it didn't (Tester2 on c8c6594).
            announceAfterSheet(undoing ? UndoText.undid(shown) : UndoText.redid(shown), progress: progress)
            // One notification for the whole batch, with the rows and accounts it touched (N5).
            updates.changed(Self.delta(of: step))
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

    /// The revert was handed off, then its window closed or its history was cleared (B1): the step goes, with no
    /// alert, notice or announcement; a write it made is posted once, so every window shows it.
    private func finishDetached(_ step: Step, result: Result<RevertResult, any Error>) {
        removeInFlight(step)
        if case .success(.reverted(let inverse, let outcome)) = result {
            step.change = inverse
            step.outcome = outcome
            updates.changed(Self.delta(of: step))
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

    private func announceAfterSheet(_ text: String, progress: BatchProgress?) {
        guard let progress else {
            announce(text)
            return
        }
        if progress.isShown {
            closingProgress = progress
        }
        progress.announceAfterSheet(text) { [weak self] in self?.announce($0) }
    }

    /// The progress sheet has closed: an announcement held for it is posted now.
    public func batchSheetDismissed() {
        closingProgress?.sheetClosed()
        closingProgress = nil
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
