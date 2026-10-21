import Foundation

/// What deleting an account takes with it (D19). The confirmation shows both counts.
public struct AccountDeletionImpact: Equatable, Sendable {
    /// Every transaction that refers to the account, transfers in either direction included.
    public var transactionCount: Int
    /// The transfers among them. Their other account's balance changes when they go.
    public var transferCount: Int

    public init(transactionCount: Int, transferCount: Int) {
        self.transactionCount = transactionCount
        self.transferCount = transferCount
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
