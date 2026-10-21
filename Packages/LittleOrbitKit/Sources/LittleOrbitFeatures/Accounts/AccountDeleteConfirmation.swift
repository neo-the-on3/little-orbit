import Foundation
import LittleOrbitDomain
import Observation

/// One window's pending "Delete “Household Card”?" prompt (D19, D167). Each window makes its own, so the
/// prompt shows only in the window that asked, and confirming records the step only in that window's history
/// (Tester's #87 B3). The accounts view model the windows share holds data only.
@MainActor
@Observable
public final class AccountDeleteConfirmation {
    public private(set) var prompt: AccountDeletePrompt?
    @ObservationIgnored private let model: AccountsViewModel

    public init(model: AccountsViewModel) {
        self.model = model
    }

    public func request(accountID: UUID) {
        prompt = model.deletePrompt(accountID: accountID)
    }

    /// Deletes the account and returns the change, for the caller to record in this window's history (#93).
    @discardableResult
    public func confirm() -> TransactionChange? {
        guard let prompt else {
            return nil
        }
        self.prompt = nil
        return model.delete(prompt)
    }

    public func hide() {
        guard let prompt else {
            return
        }
        self.prompt = nil
        model.hideInsteadOfDeleting(prompt)
    }

    public func cancel() {
        prompt = nil
    }
}
