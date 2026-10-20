import Foundation

/// The whole ledger as value types. Repositories load this, apply `LedgerBook`, then write it back.
public struct LedgerSnapshot: Equatable, Sendable {
    public var accounts: [Account]
    public var transactions: [Transaction]
    public var categories: [TransactionCategory]
    public var payees: [Payee]
    public var tags: [Tag]
    public var splits: [TransactionSplit]
    public var attachments: [Attachment]

    public init(
        accounts: [Account] = [],
        transactions: [Transaction] = [],
        categories: [TransactionCategory] = [],
        payees: [Payee] = [],
        tags: [Tag] = [],
        splits: [TransactionSplit] = [],
        attachments: [Attachment] = [],
    ) {
        self.accounts = accounts
        self.transactions = transactions
        self.categories = categories
        self.payees = payees
        self.tags = tags
        self.splits = splits
        self.attachments = attachments
    }

    public func accountsVisible() -> [Account] {
        accounts.filter { $0.deletedAt == nil }
    }

    public func transactionsVisible() -> [Transaction] {
        transactions.filter { $0.deletedAt == nil }
    }

    public func categoriesVisible() -> [TransactionCategory] {
        categories.filter { $0.deletedAt == nil }
    }

    public func payeesVisible() -> [Payee] {
        payees.filter { $0.deletedAt == nil }
    }

    public func tagsVisible() -> [Tag] {
        tags.filter { $0.deletedAt == nil }
    }

    public func splitsVisible(for transactionID: UUID? = nil) -> [TransactionSplit] {
        splits.filter { split in
            split.deletedAt == nil && (transactionID == nil || split.transactionID == transactionID)
        }
    }

    public func attachmentsVisible(for transactionID: UUID? = nil) -> [Attachment] {
        attachments.filter { attachment in
            attachment.deletedAt == nil && (transactionID == nil || attachment.transactionID == transactionID)
        }
    }
}
