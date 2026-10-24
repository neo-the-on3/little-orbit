import Foundation

extension WindowUndoHistory {
    /// After a category merge or delete, or a payee merge, in this window, which aren't undoable: its Undo and
    /// Redo history is cleared, so Undo can't reach an older change by mistake (D287.4). Other windows' steps
    /// are checked when they run (D187.5).
    public func clearAfterRemoval() {
        clear()
        alert = nil
    }
}
