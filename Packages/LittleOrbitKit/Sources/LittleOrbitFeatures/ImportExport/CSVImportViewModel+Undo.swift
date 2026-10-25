import Foundation
import LittleOrbitDomain

// MARK: Undo Import

extension CSVImportViewModel {
    public func requestUndo() {
        guard canUndo else { return }
        isConfirmingUndo = true
    }

    public func undo() {
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
}
