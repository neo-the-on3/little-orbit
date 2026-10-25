import Foundation
import LittleOrbitDomain

/// A change to a record that isn't a transaction or an account, such as a budget save (D307.8), kept as one step
/// of a window's history (D187.2). Reverting returns the inverse, which reverts in turn, so the step can be
/// undone and redone any number of times. Like a transaction step it checks first: a stale step writes nothing,
/// says why and is removed; a failure writes nothing and keeps the step (D187.5, X8).
@MainActor
public protocol RecordUndoChange {
    /// The step's name, as the Undo and Redo menus show it: “New Budget Eating out” (D198, D307.8).
    var name: String { get }
    /// Reverts the change if the ledger still holds what it left. Throws when the write fails.
    func revert() throws -> RecordRevertResult
}

/// What reverting a record step did: reverted it, with its inverse, or found it stale and wrote nothing, with
/// the alert's message, which names no cause (D228).
@MainActor
public enum RecordRevertResult {
    case reverted(any RecordUndoChange)
    case stale(message: String)
}

extension WindowUndoHistory {
    /// Records a record change the user just made in this window and returns its step's id. Like `record(_:)`
    /// for a transaction change: any toast or notice closes, Redo is cleared and every window reloads.
    @discardableResult
    public func record(_ change: any RecordUndoChange) -> UUID {
        let step = Step(record: change)
        closeAfterNewStep()
        if registrar != nil {
            undoSteps.append(step)
            register(step, as: step.name)
        }
        ledgerChanged()
        return step.id
    }

    /// A record change that couldn't be read back, so it can't be checked and isn't an Undo step (D187.5). The
    /// change itself was saved, so every window still reloads.
    public func recordWithoutStep() {
        closeAfterNewStep()
        alert = UndoAlert(title: Self.changeFailedTitle, message: Self.unreadableChange)
        ledgerChanged()
    }
}
