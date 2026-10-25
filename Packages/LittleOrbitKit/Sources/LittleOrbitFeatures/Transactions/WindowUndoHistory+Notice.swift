import Foundation
import LittleOrbitDomain

extension WindowUndoHistory {
    /// "Restored 5 transactions in Household Card" when the step is in an account other than the one on this
    /// window's screen, by the same test as the names; `nil` when it's on screen, even scrolled out of view
    /// (D187.6, N1, N2).
    func noticeAfterApplying(_ step: Step) -> UndoNotice? {
        if let account = step.account {
            if screen == .account(account.id) {
                return nil
            }
            let restoring = if case .addedAccount = step.change.core { true } else { false }
            return UndoNotice(
                message: restoring ? UndoText.restoredAccount(account.name) : UndoText.deletedAccount(account.name),
                accountID: restoring ? account.id : nil,
            )
        }
        let accounts = step.impact.accounts
        guard !accounts.isEmpty, UndoActionTitle.isOffScreen(step.impact, on: screen) else {
            return nil
        }
        let count = step.change.transactionIDs.count
        // `step.change` is the inverse now: an Undo of a delete leaves `.added`, and so on.
        let effect: UndoText.Effect =
            switch step.change.core {
            case .added: .restored
            case .removed: .deleted
            case .replaced, .removedAccount, .addedAccount, .createdPayees, .removedPayees, .savedScheduledItem,
                .revertedScheduledItemSave, .settledOccurrence, .unsettledOccurrence:
                .updated
            }
        return UndoNotice(
            message: UndoActionTitle.placed(UndoText.notice(effect, count: count), step.impact),
            accountID: accounts.first?.id,
        )
    }
}
