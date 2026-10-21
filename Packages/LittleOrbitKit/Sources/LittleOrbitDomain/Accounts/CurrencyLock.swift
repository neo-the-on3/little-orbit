import Foundation

/// D54 and D104: an account's currency locks as soon as anything refers to it.
public enum CurrencyLock {
    public static let message = "Currency can't be changed once the account has transactions or scheduled items."

    /// - Parameter scheduledAccountIDs: accounts that a scheduled item points at (#26).
    public static func isLocked(
        accountID: UUID,
        transactions: [Transaction],
        scheduledAccountIDs: Set<UUID> = [],
    ) -> Bool {
        scheduledAccountIDs.contains(accountID)
            || transactions.contains { AccountReferences.refers($0, to: accountID) }
    }
}
