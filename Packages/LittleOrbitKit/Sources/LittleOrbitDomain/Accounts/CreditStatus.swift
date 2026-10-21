import Foundation

/// Available credit for a credit card, as decided in D52 and D104 (#20).
///
/// Available credit is the credit limit minus the amount owed. A balance in credit adds to it, and it never
/// drops below 0: over the limit, `available` is 0 and `overLimitBy` holds the excess.
public struct CreditStatus: Equatable, Sendable {
    public var limit: Decimal
    public var available: Decimal
    public var overLimitBy: Decimal?

    public init(limit: Decimal, available: Decimal, overLimitBy: Decimal? = nil) {
        self.limit = limit
        self.available = available
        self.overLimitBy = overLimitBy
    }

    /// `balance` is signed: negative when money is owed on the card.
    public init(limit: Decimal, balance: Decimal) {
        let headroom = limit + balance
        self.limit = limit
        if headroom < 0 {
            self.available = 0
            self.overLimitBy = -headroom
        } else {
            self.available = headroom
            self.overLimitBy = nil
        }
    }
}

extension Account {
    /// The available-credit line for this account, or `nil` when none is shown.
    ///
    /// Only credit cards that have a limit and 'Show available credit' on show it. Loans and cards without a
    /// limit never do (D104).
    public func creditStatus(balance: Decimal) -> CreditStatus? {
        guard type == .creditCard, showAvailableCredit, let creditLimit else {
            return nil
        }
        return CreditStatus(limit: creditLimit, balance: balance)
    }
}
