import Foundation

/// A snapshot with the lookups the transaction rules need, built once in O(T + S) (#285): live accounts,
/// categories, payees and tags by id, where each transaction is stored, the live splits of each transaction and
/// the live refunds linked to each original. The rules read it instead of scanning the snapshot, so a batch
/// checks every row against one index, and a single save builds one for its row.
///
/// Each lookup gives what the snapshot scan it replaces gives: the first match in stored order. `replace(at:with:)`
/// and `append(_:)` change a transaction in `snapshot` and keep the lookups in step, so a later row sees what an
/// earlier one did. Accounts, categories, tags and splits don't change while a transaction is saved. A plain
/// value, so it can be built and used off the main actor.
public struct LedgerIndex: Sendable {
    /// The indexed ledger, with every change made through this index.
    public private(set) var snapshot: LedgerSnapshot
    private var accounts: [UUID: Account] = [:]
    private var categories: [UUID: TransactionCategory] = [:]
    /// The position of each live payee in `snapshot.payees`.
    private var payees: [UUID: Int] = [:]
    private var tags: Set<UUID> = []
    /// The first position of each transaction id in `snapshot.transactions`, deleted or not.
    private var positions: [UUID: Int] = [:]
    /// The first position of each id where the transaction is live.
    private var livePositions: [UUID: Int] = [:]
    /// The live splits of each transaction, in stored order.
    private var splits: [UUID: [TransactionSplit]] = [:]
    /// The positions of the live refunds linked to each original, in stored order.
    private var refunds: [UUID: [Int]] = [:]

    public init(_ snapshot: LedgerSnapshot) {
        self.snapshot = snapshot
        for account in snapshot.accounts where account.deletedAt == nil && accounts[account.id] == nil {
            accounts[account.id] = account
        }
        for category in snapshot.categories where category.deletedAt == nil && categories[category.id] == nil {
            categories[category.id] = category
        }
        for (position, payee) in snapshot.payees.enumerated() where payee.deletedAt == nil && payees[payee.id] == nil {
            payees[payee.id] = position
        }
        for tag in snapshot.tags where tag.deletedAt == nil {
            tags.insert(tag.id)
        }
        positions.reserveCapacity(snapshot.transactions.count)
        livePositions.reserveCapacity(snapshot.transactions.count)
        for (position, transaction) in snapshot.transactions.enumerated() {
            indexTransaction(transaction, at: position)
        }
        for split in snapshot.splits where split.deletedAt == nil {
            if let transactionID = split.transactionID {
                splits[transactionID, default: []].append(split)
            }
        }
    }

    // MARK: Lookups

    /// The live account with this id, as `LedgerBook.activeAccount(_:in:)` finds it.
    func account(_ id: UUID) -> Account? {
        accounts[id]
    }

    /// The live category with this id, as `LedgerBook.activeCategory(_:in:)` finds it.
    func category(_ id: UUID) -> TransactionCategory? {
        categories[id]
    }

    func hasPayee(_ id: UUID) -> Bool {
        payees[id] != nil
    }

    func hasTag(_ id: UUID) -> Bool {
        tags.contains(id)
    }

    /// Where the transaction with this id is stored, deleted or not.
    func position(of id: UUID) -> Int? {
        positions[id]
    }

    /// The live transaction with this id.
    func liveTransaction(_ id: UUID) -> Transaction? {
        livePositions[id].map { snapshot.transactions[$0] }
    }

    /// The live splits of the transaction, in stored order.
    func liveSplits(of transactionID: UUID) -> [TransactionSplit] {
        splits[transactionID] ?? []
    }

    /// The positions of the live refunds linked to `originalID`, in stored order.
    func refundPositions(of originalID: UUID) -> [Int] {
        refunds[originalID] ?? []
    }

    /// The live refunds linked to `originalID`, in stored order: `LedgerBook.linkedRefunds(of:in:)`.
    func linkedRefunds(of originalID: UUID) -> [Transaction] {
        refundPositions(of: originalID).map { snapshot.transactions[$0] }
    }

    // MARK: Changes

    /// Replaces the transaction at `position` with a version of the same transaction.
    mutating func replace(at position: Int, with transaction: Transaction) {
        let old = snapshot.transactions[position]
        snapshot.transactions[position] = transaction
        if let originalID = old.refundOfID, old.deletedAt == nil {
            refunds[originalID]?.removeAll { $0 == position }
            if refunds[originalID]?.isEmpty == true {
                refunds[originalID] = nil
            }
        }
        if let originalID = transaction.refundOfID, transaction.deletedAt == nil {
            insertRefund(at: position, of: originalID)
        }
        if transaction.deletedAt == nil {
            if livePositions[transaction.id].map({ $0 > position }) ?? true {
                livePositions[transaction.id] = position
            }
        } else if livePositions[transaction.id] == position {
            // Rare, a save of a deleted version: the next live one with this id, if the snapshot repeats it.
            livePositions[transaction.id] = snapshot.transactions.indices.first { index in
                snapshot.transactions[index].id == transaction.id && snapshot.transactions[index].deletedAt == nil
            }
        }
    }

    /// Adds a transaction after the stored ones.
    mutating func append(_ transaction: Transaction) {
        snapshot.transactions.append(transaction)
        indexTransaction(transaction, at: snapshot.transactions.count - 1)
    }

    /// `replace(at:with:)` where the transaction is stored, otherwise `append(_:)`, as `replaceOrAppend` does.
    mutating func replaceOrAppend(_ transaction: Transaction) {
        if let position = positions[transaction.id] {
            replace(at: position, with: transaction)
        } else {
            append(transaction)
        }
    }

    /// Changes the live payee with this id in place. Payees stay live, so the lookups don't change.
    mutating func updatePayee(_ id: UUID, _ change: (inout Payee) -> Void) {
        if let position = payees[id] {
            change(&snapshot.payees[position])
        }
    }

    private mutating func indexTransaction(_ transaction: Transaction, at position: Int) {
        if positions[transaction.id] == nil {
            positions[transaction.id] = position
        }
        guard transaction.deletedAt == nil else {
            return
        }
        if livePositions[transaction.id] == nil {
            livePositions[transaction.id] = position
        }
        if let originalID = transaction.refundOfID {
            insertRefund(at: position, of: originalID)
        }
    }

    /// Keeps each original's refunds in stored order; an original has only a few.
    private mutating func insertRefund(at position: Int, of originalID: UUID) {
        var list = refunds[originalID] ?? []
        let slot = list.firstIndex { $0 > position } ?? list.endIndex
        list.insert(position, at: slot)
        refunds[originalID] = list
    }
}
