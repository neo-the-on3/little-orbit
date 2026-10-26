import Foundation
import LittleOrbitDomain

// MARK: Undo Import

extension CSVImportViewModel {
    /// N1 on #261: the sheet hears the store-change signal a Task hop after a change, so both entry points check
    /// the revision themselves first. A change in the same step, such as a watch Skip, still ends Undo Import.
    public func requestUndo() {
        endUndoWindowIfDataChanged()
        guard canUndo else { return }
        isConfirmingUndo = true
    }

    public func undo() {
        endUndoWindowIfDataChanged()
        guard let receipt, canUndo else { return }
        do {
            try useCases.ledger.undo(receipt)
            isUndone = true
            changed()
            ImportLog.event(.undone)
        } catch let error as ImportUndoError where error == .changedSinceImport {
            alert = ImportAlert(title: ImportExportText.undoRefusedTitle, message: ImportExportText.undoChangedMessage)
        } catch {
            ImportLog.event(.undoFailed)
            alert = ImportAlert(title: ImportExportText.undoFailedTitle, message: ImportExportText.undoFailedMessage)
        }
    }

    /// D108, D381.4: any change to the store after the import's own one ends Undo Import: a watch Pay or Skip
    /// the iPhone records, an automatic posting, an edit in another window or a restore. It's tracked by the
    /// shared store-change signal rather than by comparing ledgers, because a Skip changes only the scheduled
    /// item. The import's own change set `importRevision`, so it doesn't count; settings changes don't move the
    /// signal. The summary then no longer shows Undo Import, and an open confirmation closes. Undoing the change
    /// that ended it doesn't bring it back. VoiceOver focus moves to the summary's title only if it was on Undo
    /// Import or the confirmation was open (V1), so it's read before the confirmation closes.
    func endUndoWindowIfDataChanged() {
        guard let importRevision, !isUndone, !isUndoWindowOver, revision() != importRevision else { return }
        let wasConfirmationOpen = isConfirmingUndo
        isUndoWindowOver = true
        isConfirmingUndo = false
        movesFocusToSummaryTitle = isUndoFocused || wasConfirmationOpen
        ImportLog.event(.undoEnded)
    }
}
