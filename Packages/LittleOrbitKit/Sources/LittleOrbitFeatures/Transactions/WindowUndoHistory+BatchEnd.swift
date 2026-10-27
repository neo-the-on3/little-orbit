import Foundation
import LittleOrbitCore

// MARK: The end of a batch Undo or Redo that wrote (#285; D403.1 and D405, Tester2 on 1f2eae8)
//
// At 1f2eae8 the batch ended at the install, then the change was posted and every window refreshed on the main
// actor (`window.recompute`, `history.rows`, `ui.table.update`: 0.44–0.59 s) while the sheet was still up. That
// froze the sheet, counting towards the D405 pause, and a menu Undo or Redo clicked then ran once main was free,
// since busy had gone and the recorded end was before the click's event. Now:
// 1. The sheet closes at once; busy stays on, and the run can't be cancelled any more.
// 2. Once the sheet has gone (`BatchProgress.sheetHasGone()`), the one change notice goes out, and every window
//    refreshes with nothing over it.
// 3. Once every refresh is done and the main actor is free (`LedgerUpdates.settle()`), the batch ends, recording
//    its end then; the notice and the announcement follow, so VoiceOver still hears it after the sheet has gone.

extension WindowUndoHistory {
    /// The revert wrote `step` (its `change` and `outcome` are the new ones). If the window closed or its history
    /// was cleared meanwhile (`cancelBatch`, B1), the change is still posted once and busy still ends with the
    /// refresh, but the step goes, with no notice or announcement.
    func finishReverted(_ step: Step, undoing: Bool, title shown: String) async {
        let span = BatchTrace.begin("batch.finish")
        defer { span.end() }
        // It wrote: from here nothing stops it, on or off the main actor.
        batchRun?.isHandedOff = true
        if let progress = closeBatchSheet(), batchRun?.isDetached == false {
            let wait = BatchTrace.begin("batch.finish.sheetGone")
            await progress.sheetHasGone()
            wait.end()
        }
        // One notification for the whole batch, with the rows and accounts it touched (N5).
        let refresh = BatchTrace.begin("batch.finish.refresh")
        updates.changed(Self.delta(of: step))
        await updates.settle()
        refresh.end()
        let detached = batchRun?.isDetached ?? true
        batchRun = nil
        updates.endBatch()
        closingProgress = nil
        if detached {
            removeInFlight(step)
        } else {
            notice = noticeAfterApplying(step)
            BatchTrace.event("batch.announce.afterRefresh")
            announce(undoing ? UndoText.undid(shown) : UndoText.redid(shown))
        }
        refreshMenu()
    }

    /// Takes the sheet down, keeping its progress drawn while it closes: the progress if the sheet showed.
    private func closeBatchSheet() -> BatchProgress? {
        guard let progress = batchProgress else {
            return nil
        }
        progress.finish()
        batchProgress = nil
        guard progress.isShown else {
            return nil
        }
        closingProgress = progress
        BatchTrace.event("batch.sheet.closeAtInstall")
        return progress
    }
}
