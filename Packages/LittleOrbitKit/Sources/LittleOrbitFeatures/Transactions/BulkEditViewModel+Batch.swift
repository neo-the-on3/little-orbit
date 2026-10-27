import Foundation
import LittleOrbitCore
import LittleOrbitDomain

extension BulkEditViewModel {
    /// Whether Apply is running, so the sheet shows its progress and can't be closed or applied again.
    public var isApplying: Bool { progress != nil }

    /// Applies the ticked fields as one batch (#285, D398): the rows are checked off the main actor, with progress
    /// for the sheet, then written in one change, as `apply()` does. Returns the change, or `nil` with `alert` or
    /// `errorMessage` set, when nothing was written. While another window's batch runs, or this one's, it starts
    /// nothing. Cancelled before the write, it writes nothing.
    ///
    /// It ends as a batch Undo or Redo does (D403, D405; Tech Architect on 3dc318b): the save runs off the main
    /// actor, then the sheet closes (`closeRequested`) and, if its progress showed, Apply waits for it to go before
    /// installing the save. Then `record` registers the step and posts the change, the windows' counted refreshes
    /// run, the batch ends, and VoiceOver hears how many rows changed. Busy is held throughout, so a click queued
    /// behind the sheet is dropped while the batch's rows are still being redrawn, not run against them.
    /// `record` isn't called for an Apply that changed no row (D402): nothing to undo, no change to post.
    public func applyInBackground(
        record: @escaping @MainActor (TransactionChange) -> Void = { _ in }
    ) async -> TransactionChange? {
        guard progress == nil, let request = request() else {
            return nil
        }
        guard updates?.beginBatch() ?? true else {
            return nil
        }
        let span = BatchTrace.begin("batch.apply")
        defer { span.end() }
        let progress = BatchProgress(
            kind: .applying,
            total: request.selection.count,
            showAfter: progressShowDelay,
            now: progressClock,
        )
        self.progress = progress
        do {
            var reporter = progress.start()
            reporter.willInstall = { [weak self] in await self?.closeSheet(progress, "batch.sheet.closeBeforeInstall") }
            // The phase first: the UI draws Applying before any work starts (N5).
            await BatchProgress.uiTurn()
            let change = try await applyUseCase.apply(request, reporting: reporter)
            await finishApplied(change, progress: progress, record: record)
            return change
        } catch is CancellationError {
            endUnwritten(progress)
            return nil
        } catch {
            endUnwritten(progress)
            refused(error)
            return nil
        }
    }

    /// After the write: the sheet goes first (if the hook before the install hasn't closed it already), then the
    /// step and its change, the counted refreshes, the batch's end and, last, the announcement (D403).
    private func finishApplied(
        _ change: TransactionChange,
        progress: BatchProgress,
        record: @MainActor (TransactionChange) -> Void,
    ) async {
        let span = BatchTrace.begin("batch.finish")
        defer { span.end() }
        await closeSheet(progress, "batch.sheet.closeAtInstall")
        // No row changed: nothing to undo, so no “Undo Edit 0 Transactions” step (Tester2, N5).
        if !change.changesNoTransaction {
            record(change)
        }
        let refresh = BatchTrace.begin("batch.finish.refresh")
        await updates?.settle()
        refresh.end()
        updates?.endBatch()
        // VoiceOver hears that Apply finished, and how many rows changed (Tester2, N5), after the sheet has closed
        // (Tester2 on c8c6594) and the windows have redrawn.
        BatchTrace.event("batch.announce.afterRefresh")
        announce(BulkEditText.appliedAnnouncement(count: change.transactionIDs.count))
    }

    /// Asks the sheet to close and, if its progress showed, waits until it has gone. The progress stays drawn while
    /// it closes. Once only: the second call returns at once.
    private func closeSheet(_ progress: BatchProgress, _ closed: StaticString) async {
        guard self.progress === progress else {
            return
        }
        progress.finish()
        self.progress = nil
        closeRequested = true
        guard progress.isShown else {
            return
        }
        closingProgress = progress
        BatchTrace.event(closed)
        BatchTrace.mainBacklog("batch.sheet.closeBacklog")
        let wait = BatchTrace.begin("batch.finish.sheetGone")
        await progress.sheetHasGone()
        wait.end()
    }

    /// Nothing was written: the sheet stays, with its fields, and the batch ends now.
    private func endUnwritten(_ progress: BatchProgress) {
        progress.finish()
        if self.progress === progress {
            self.progress = nil
        }
        updates?.endBatch()
    }

    /// The Bulk Edit sheet has closed: an announcement held for it is posted now.
    public func sheetClosed() {
        closingProgress?.sheetClosed()
        closingProgress = nil
    }
}
