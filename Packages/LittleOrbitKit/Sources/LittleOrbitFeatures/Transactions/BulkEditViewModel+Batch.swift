import Foundation
import LittleOrbitCore
import LittleOrbitDomain

extension BulkEditViewModel {
    /// Whether Apply is running, so the sheet shows its progress and can't be closed or applied again.
    public var isApplying: Bool { progress != nil }

    /// Applies the ticked fields as one batch (#285, D398): the rows are checked off the main actor, with progress
    /// for the sheet, then written in one change, as `apply()` does. Returns the change to register for Undo, or
    /// `nil` with `alert` or `errorMessage` set, when nothing was written. While another window's batch runs,
    /// or this one's, it starts nothing. Cancelled before the write, it writes nothing.
    public func applyInBackground() async -> TransactionChange? {
        guard progress == nil, let request = request() else {
            return nil
        }
        guard updates?.beginBatch() ?? true else {
            return nil
        }
        let span = BatchTrace.begin("batch.apply")
        let progress = BatchProgress(kind: .applying, total: request.selection.count, now: progressClock)
        self.progress = progress
        defer {
            span.end()
            progress.finish()
            self.progress = nil
            updates?.endBatch()
        }
        do {
            let reporter = progress.start()
            // The phase first: the UI draws Applying before any work starts (N5).
            await BatchProgress.uiTurn()
            let change = try await applyUseCase.apply(request, reporting: reporter)
            // VoiceOver hears that Apply finished, and how many rows changed (Tester2, N5): once the sheet has
            // closed if the progress showed, now if it didn't (Tester2 on c8c6594).
            if progress.isShown {
                closingProgress = progress
            }
            progress.announceAfterSheet(
                BulkEditText.appliedAnnouncement(count: change.transactionIDs.count),
                post: announce,
            )
            return change
        } catch is CancellationError {
            return nil
        } catch {
            refused(error)
            return nil
        }
    }

    /// The Bulk Edit sheet has closed: an announcement held for it is posted now.
    public func sheetClosed() {
        closingProgress?.sheetClosed()
        closingProgress = nil
    }
}
