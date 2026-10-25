import Foundation

/// A transaction removed by a delete, with what went with it, so Undo can put it all back (D19, S14).
public struct RemovedTransaction: Equatable, Sendable {
    public var transaction: Transaction
    public var attachments: [Attachment]
    public var splits: [TransactionSplit]
    /// The refunds the delete unlinked from this expense, so Undo links exactly these again (D19, #55).
    public var unlinkedRefundIDs: [UUID]

    public init(
        transaction: Transaction,
        attachments: [Attachment] = [],
        splits: [TransactionSplit] = [],
        unlinkedRefundIDs: [UUID] = [],
    ) {
        self.transaction = transaction
        self.attachments = attachments
        self.splits = splits
        self.unlinkedRefundIDs = unlinkedRefundIDs
    }
}

/// A payee found or saved for a typed name, and whether this call saved it (`SaveTransactionsUseCase`).
public struct ResolvedPayee: Equatable, Sendable {
    public var payee: Payee
    public var isNew: Bool

    public init(payee: Payee, isNew: Bool) {
        self.payee = payee
        self.isNew = isNew
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
    /// A save that also created these payees from typed text (D191.4). Revert reverts the save, then
    /// removes each payee that nothing else uses and no one has changed since; any other stays, silently.
    indirect case createdPayees([Payee], TransactionChange)
    /// Revert by putting these payees back, with the same IDs, then reverting the change (Redo, D191.4a.3).
    indirect case removedPayees([Payee], TransactionChange)
    /// A save of the Scheduled form: "New Scheduled Item Rent" or "Edit Rent" (D351.1). Revert by putting the item
    /// back as it was, or removing a new one, with the payee the save created or unarchived.
    case savedScheduledItem(ScheduledItemSaveChange)
    /// Revert by saving the item again as the form left it, with its payee (Redo, D351.1).
    case revertedScheduledItemSave(ScheduledItemSaveChange)
    /// A manual Pay or Skip of a scheduled occurrence (D288.3). Revert by unsettling it: a Pay's transaction is
    /// deleted and the occurrence is due again.
    case settledOccurrence(ScheduledSettlementChange)
    /// Revert by settling the occurrence again as it was, a Pay's transaction with its own ID (Redo, D288.3).
    case unsettledOccurrence(ScheduledSettlementChange)

    /// `change`, plus the payees its save created, if any.
    public static func saved(_ change: TransactionChange, creating payees: [Payee]) -> TransactionChange {
        payees.isEmpty ? change : .createdPayees(payees, change)
    }

    /// `change`, plus the payees Undo removed with it, if any, for Redo to put back.
    static func saved(_ change: TransactionChange, removing payees: [Payee]) -> TransactionChange {
        payees.isEmpty ? change : .removedPayees(payees, change)
    }

    /// This change with every use of one payee moved to another.
    func replacingPayee(_ payeeID: UUID, with otherID: UUID) -> TransactionChange {
        func moved(_ transaction: Transaction) -> Transaction {
            var transaction = transaction
            if transaction.payeeID == payeeID {
                transaction.payeeID = otherID
            }
            return transaction
        }
        func moved(_ item: RemovedTransaction) -> RemovedTransaction {
            var item = item
            item.transaction = moved(item.transaction)
            return item
        }
        switch self {
        case .removed(let items): return .removed(items.map(moved))
        case .replaced(let versions): return .replaced(versions.map(moved))
        case .removedAccount(var removed):
            removed.transactions = removed.transactions.map(moved)
            return .removedAccount(removed)
        case .createdPayees(let payees, let change):
            return .createdPayees(payees, change.replacingPayee(payeeID, with: otherID))
        case .removedPayees(let payees, let change):
            return .removedPayees(payees, change.replacingPayee(payeeID, with: otherID))
        case .added, .addedAccount, .savedScheduledItem, .revertedScheduledItemSave, .settledOccurrence,
            .unsettledOccurrence:
            return self
        }
    }

    /// The transaction or account change itself, without the payees that come and go with it.
    public var core: TransactionChange {
        switch self {
        case .createdPayees(_, let change), .removedPayees(_, let change): change.core
        case .removed, .added, .replaced, .removedAccount, .addedAccount, .savedScheduledItem,
            .revertedScheduledItemSave, .settledOccurrence, .unsettledOccurrence:
            self
        }
    }

    /// The transactions the change touches.
    public var transactionIDs: [UUID] {
        switch core {
        case .removed(let items): items.map(\.transaction.id)
        case .added(let ids): ids
        case .replaced(let items): items.map(\.id)
        case .removedAccount(let removed): removed.transactions.map(\.transaction.id)
        case .settledOccurrence(let change), .unsettledOccurrence(let change): change.transaction.map { [$0.id] } ?? []
        case .addedAccount, .createdPayees, .removedPayees, .savedScheduledItem, .revertedScheduledItemSave: []
        }
    }

    /// A Bulk Edit Apply that changed no row and wrote nothing: there is nothing to undo, so it gets no Undo step
    /// (Tester2, N5). A change that also created a payee isn't one: Undo removes that payee.
    public var changesNoTransaction: Bool {
        if case .replaced(let items) = self {
            return items.isEmpty
        }
        return false
    }

    /// The account a whole-account change is about; empty for transaction changes.
    public var accountIDs: [UUID] {
        switch core {
        case .removedAccount(let removed): [removed.account.id]
        case .addedAccount(let id): [id]
        case .removed, .added, .replaced, .createdPayees, .removedPayees, .savedScheduledItem,
            .revertedScheduledItemSave, .settledOccurrence, .unsettledOccurrence:
            []
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
