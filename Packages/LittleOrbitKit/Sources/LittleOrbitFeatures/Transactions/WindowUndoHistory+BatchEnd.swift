import Foundation
import LittleOrbitCore

// MARK: The end of a batch Undo or Redo that wrote (#285; D403.1 and D405, Tester2 on 1f2eae8 and 3dc318b)
//
// At 1f2eae8 the windows refreshed while the sheet was up. At 3dc318b the refresh came after the sheet had gone, but
// main was still busy for 0.31–0.35 s with the sheet up right after the install: the install swaps the main context
// for a fresh one, and the old one's records are torn down on the main queue after it. Now, for a save off the main
// actor:
// 1. Once the save has finished, before the install (`LedgerBatchReporter.willInstall`), the sheet closes; busy stays
//    on, and the run can't be cancelled any more. The install waits until the sheet has gone
//    (`BatchProgress.sheetHasGone()`). Until then the window still shows the rows from before the batch.
// 2. The install, then the one change notice; every window refreshes with nothing over it.
// 3. Once every refresh is done and the main actor is free (`LedgerUpdates.settle()`), the batch ends, recording
//    its end then; the notice and the announcement follow, so VoiceOver still hears it after the sheet has gone.
// A store that saves on the main actor has no separate install: the sheet closes once the revert returns.

extension WindowUndoHistory {
    /// The revert wrote `step` (its `change` and `outcome` are the new ones). If the window closed or its history
    /// was cleared meanwhile (`cancelBatch`, B1), the change is still posted once and busy still ends with the
    /// refresh, but the step goes, with no notice or announcement.
    func finishReverted(_ step: Step, undoing: Bool, title shown: String) async {
        let span = BatchTrace.begin("batch.finish")
        defer { span.end() }
        // It wrote: from here nothing stops it, on or off the main actor.
        batchRun?.isHandedOff = true
        // Already gone for a save off the main actor (`closeSheetBeforeInstall`).
        await waitForSheetToGo("batch.sheet.closeAtInstall")
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

    /// The save off the main actor has finished; its result isn't installed yet. The sheet closes, and the install
    /// waits until it has gone, so its main-actor work doesn't freeze the sheet (D405 on 3dc318b).
    func closeSheetBeforeInstall(_ stepID: ObjectIdentifier) async {
        guard let run = batchRun, ObjectIdentifier(run.step) == stepID else {
            return
        }
        batchRun?.isHandedOff = true
        await waitForSheetToGo("batch.sheet.closeBeforeInstall")
    }

    /// Takes the sheet down, signposting `closed`, and waits for it to go, unless the run was detached. Nothing
    /// when it's already down.
    private func waitForSheetToGo(_ closed: StaticString) async {
        guard let progress = closeBatchSheet() else {
            return
        }
        BatchTrace.event(closed)
        BatchTrace.mainBacklog("batch.sheet.closeBacklog")
        guard batchRun?.isDetached == false else {
            return
        }
        let wait = BatchTrace.begin("batch.finish.sheetGone")
        await progress.sheetHasGone()
        wait.end()
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
        return progress
    }
}
