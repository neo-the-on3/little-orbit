import Foundation

/// The one definition of an account's balance (D21).
///
/// - **Current**: the opening balance plus every transaction dated up to today, on its own calendar day in the
///   time zone it was entered in. Upcoming transactions are left out until their day. The account list, net
///   wealth, the account header and the repository's `balance(of:today:)` and `netWorth(today:)` all use it.
/// - **Projected**: also counts Upcoming transactions. Only the history's projected balances and
///   "After upcoming" use it.
public enum AccountBalance {
    public static func current(of accountID: UUID, in snapshot: LedgerSnapshot, today: CalendarDay) throws -> Decimal {
        try LedgerBook.balance(of: accountID, in: dated(upTo: today, snapshot))
    }

    public static func projected(of accountID: UUID, in snapshot: LedgerSnapshot) throws -> Decimal {
        try LedgerBook.balance(of: accountID, in: snapshot)
    }

    /// Per-currency current balances of the accounts that count toward net wealth.
    public static func currentNetWorth(in snapshot: LedgerSnapshot, today: CalendarDay) throws -> [String: Decimal] {
        try LedgerBook.netWorth(in: dated(upTo: today, snapshot))
    }

    private static func dated(upTo today: CalendarDay, _ snapshot: LedgerSnapshot) -> LedgerSnapshot {
        var snapshot = snapshot
        snapshot.transactions = TransactionTiming.dated(upTo: today, snapshot.transactions)
        return snapshot
    }
}
