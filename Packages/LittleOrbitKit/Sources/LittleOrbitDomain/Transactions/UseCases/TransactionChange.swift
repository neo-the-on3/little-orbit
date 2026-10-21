import Foundation

/// A transaction removed by a delete, with what went with it, so Undo can put it all back (D19, S14).
public struct RemovedTransaction: Equatable, Sendable {
    public var transaction: Transaction
    public var attachments: [Attachment]
    public var splits: [TransactionSplit]

    public init(transaction: Transaction, attachments: [Attachment] = [], splits: [TransactionSplit] = []) {
        self.transaction = transaction
        self.attachments = attachments
        self.splits = splits
    }
}

/// An account removed by a delete, with every transaction that went with it (either side of a transfer),
/// so Undo can restore it all (#93, D164.5).
public struct RemovedAccount: Equatable, Sendable {
    public var account: Account
    public var transactions: [RemovedTransaction]

    public init(account: Account, transactions: [RemovedTransaction]) {
        self.account = account
        self.transactions = transactions
    }
}

/// One revertible change to the ledger. Reverting a change returns its inverse, which reverts it in turn, so
/// a change can be undone and redone any number of times. The history of changes is kept by the caller, one
/// per window (D161, D187).
public enum TransactionChange: Equatable, Sendable {
    /// Revert by restoring these.
    case removed([RemovedTransaction])
    /// Revert by deleting these new transactions.
    case added([UUID])
    /// Revert by saving these earlier versions back.
    case replaced([Transaction])
    /// Revert by restoring the account and its transactions.
    case removedAccount(RemovedAccount)
    /// Revert by deleting the account again, with its transactions.
    case addedAccount(UUID)

    /// The transactions the change touches.
    public var transactionIDs: [UUID] {
        switch self {
        case .removed(let items): items.map(\.transaction.id)
        case .added(let ids): ids
        case .replaced(let items): items.map(\.id)
        case .removedAccount(let removed): removed.transactions.map(\.transaction.id)
        case .addedAccount: []
        }
    }

    /// The account a whole-account change is about; empty for transaction changes.
    public var accountIDs: [UUID] {
        switch self {
        case .removedAccount(let removed): [removed.account.id]
        case .addedAccount(let id): [id]
        case .removed, .added, .replaced: []
        }
    }
}

/// A transfer a change touches, in one of its versions: the account the money leaves and the one it goes to.
public struct TransferImpact: Equatable, Sendable {
    public var transactionID: UUID
    public var sourceAccountID: UUID
    public var destinationAccountID: UUID

    public init(transactionID: UUID, sourceAccountID: UUID, destinationAccountID: UUID) {
        self.transactionID = transactionID
        self.sourceAccountID = sourceAccountID
        self.destinationAccountID = destinationAccountID
    }
}

/// What a change touches in the ledger, before and after it (D166.3). It holds facts only; how a screen
/// words or shows them is up to the caller.
public struct ChangeImpact: Equatable, Sendable {
    /// Every account any version touches, on either side of a transfer, whether or not it still exists.
    public var accountIDs: Set<UUID>
    /// The accounts in `accountIDs` that still exist.
    public var accounts: [Account]
    /// The transactions the change touches.
    public var transactionIDs: [UUID]
    /// One entry per touched version that is a transfer, the earlier versions first and the current one last.
    public var transfers: [TransferImpact]

    public init(
        accountIDs: Set<UUID> = [],
        accounts: [Account] = [],
        transactionIDs: [UUID] = [],
        transfers: [TransferImpact] = [],
    ) {
        self.accountIDs = accountIDs
        self.accounts = accounts
        self.transactionIDs = transactionIDs
        self.transfers = transfers
    }
}
