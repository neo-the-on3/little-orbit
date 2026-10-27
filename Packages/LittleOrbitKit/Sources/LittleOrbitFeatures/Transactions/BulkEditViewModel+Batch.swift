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
        let progress = BatchProgress(kind: .applying, total: request.selection.count)
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
            return try await applyUseCase.apply(request, reporting: reporter)
        } catch is CancellationError {
            return nil
        } catch {
            refused(error)
            return nil
        }
    }
}
