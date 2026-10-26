import Foundation
import LittleOrbitDomain

/// Saving an edit (#264, D391): it goes through the update path, which refuses a transaction deleted elsewhere
/// while the form was open, say in another window, and resolves a typed payee in the same all-or-nothing write.
extension TransactionFormViewModel {
    /// Saves the edit and returns its change, or `nil` with the alert or error message set.
    func saveEdit(_ draft: TransactionDraft) -> TransactionChange? {
        var draft = draft
        // As a new transaction's save resolves it: none on a transfer, else the chosen one, else the typed name.
        draft.payeeID = type == .transfer ? nil : payeeID
        let typedName = type == .transfer || payeeID != nil ? nil : TransactionText.trimmed(payeeText)
        let transaction = draft.transaction(accounts: accounts, now: now())
        do {
            if let typedName {
                return try saveTransactions.update(transaction, payeeNamed: typedName, createdAt: now())
            }
            return try saveTransactions.update(transaction)
        } catch LedgerValidationError.missingTransaction {
            // Nothing was written, no payee was created and no step is recorded; OK closes the form (D391.1).
            alert = Self.deletedAlert(name: original.flatMap { StaleText.label(of: $0, payees: payees) })
            alertClosesForm = true
            return nil
        } catch {
            errorMessage = AccountHistoryViewModel.message(for: error)
            return nil
        }
    }

    /// Whether the alert shows, for its `isPresented` binding. Any dismissal, OK or Esc, clears it; after a delete
    /// elsewhere it also asks the form to close (`closeRequested`), so the form never stays open behind it (#264).
    public var isAlertPresented: Bool {
        get { alert != nil }
        set {
            guard !newValue, alert != nil else {
                return
            }
            alert = nil
            if alertClosesForm {
                closeRequested = true
            }
        }
    }

    /// The alert's OK: dismisses it, and returns `true` when the form closes with it (#264).
    @discardableResult
    public func acknowledgeAlert() -> Bool {
        isAlertPresented = false
        return alertClosesForm
    }

    /// “Couldn’t Save Changes” / “Corner Bakery has been deleted. Nothing was changed.”, naming the transaction as
    /// the Undo alerts do, payee then description (D392), or “This transaction …” when there's neither (D391.2).
    static func deletedAlert(name: String?) -> CategoryAlert {
        CategoryAlert(
            title: CategoryText.couldntSaveTitle,
            message: name.map(StaleText.deleted) ?? StaleText.thisTransactionDeleted,
        )
    }
}
