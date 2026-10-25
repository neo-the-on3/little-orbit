import Foundation

/// What deleting an account takes with it (D19). The confirmation shows both counts.
public struct AccountDeletionImpact: Equatable, Sendable {
    /// Every transaction that refers to the account, transfers in either direction included.
    public var transactionCount: Int
    /// The transfers among them. Their other account's balance changes when they go.
    public var transferCount: Int
    /// The scheduled items on the account, either side of a transfer: the delete deletes them too, and its Undo
    /// restores them (D288).
    public var scheduledItemCount: Int
    /// The scheduled transfers among them, to or from another account.
    public var scheduledTransferCount: Int

    public init(
        transactionCount: Int,
        transferCount: Int,
        scheduledItemCount: Int = 0,
        scheduledTransferCount: Int = 0,
    ) {
        self.transactionCount = transactionCount
        self.transferCount = transferCount
        self.scheduledItemCount = scheduledItemCount
        self.scheduledTransferCount = scheduledTransferCount
    }

    /// This impact with the scheduled items among `items` that are on `accountID`, either side of a transfer (D288).
    public func adding(scheduled items: [ScheduledItem], accountID: UUID) -> AccountDeletionImpact {
        let onAccount = items.filter { $0.accountID == accountID || $0.transferAccountID == accountID }
        var impact = self
        impact.scheduledItemCount = onAccount.count
        impact.scheduledTransferCount = onAccount.filter { $0.type == .transfer }.count
        return impact
    }
}

public struct AssessAccountDeletion: Sendable {
    public init() {}

    public func callAsFunction(accountID: UUID, transactions: [Transaction]) -> AccountDeletionImpact {
        let affected = transactions.filter { AccountReferences.refers($0, to: accountID) }
        return AccountDeletionImpact(
            transactionCount: affected.count,
            transferCount: affected.filter { $0.type == .transfer }.count,
        )
    }
}
