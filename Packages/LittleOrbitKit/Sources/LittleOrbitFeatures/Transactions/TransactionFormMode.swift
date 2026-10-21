import Foundation

public enum TransactionFormMode: Equatable, Sendable {
    /// From an account (its id) or from the home screen (`nil`: the last used account).
    case new(accountID: UUID?)
    case edit(UUID)

    /// A new entry opens on the amount, so fast entry is "+, type 250, Save"; an edit opens with nothing
    /// focused.
    public var focusesAmountOnOpen: Bool {
        if case .new = self {
            return true
        }
        return false
    }
}
