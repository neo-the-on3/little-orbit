import Foundation

/// Domain operations for the ledger. A repository persists the returned snapshot only after these succeed.
public enum LedgerBook {
    /// The balance counting every transaction, Upcoming ones included: the projected balance. For the
    /// balance shown as current, use `AccountBalance.current(of:in:today:)` (D21).
    public static func balance(of accountID: UUID, in snapshot: LedgerSnapshot) throws -> Decimal {
        guard let account = snapshot.accounts.first(where: { $0.id == accountID && $0.deletedAt == nil }) else {
            throw LedgerValidationError.unknownAccount
        }
        var total = account.openingBalance
        for transaction in snapshot.transactions where transaction.deletedAt == nil {
            total += effect(of: transaction, on: accountID)
        }
        return total
    }

    /// Signed contribution of one transaction to one account.
    ///
    /// Income adds `amount`. Expense subtracts `amount`. A transfer subtracts `amount` from the source and adds
    /// `destinationAmount ?? amount` to the destination. Transactions dated before the opening date still count.
    public static func effect(of transaction: Transaction, on accountID: UUID) -> Decimal {
        switch transaction.type {
        case .income:
            return transaction.accountID == accountID ? transaction.amount : 0
        case .expense:
            return transaction.accountID == accountID ? -transaction.amount : 0
        case .transfer:
            if transaction.accountID == accountID {
                return -transaction.amount
            }
            if transaction.transferAccountID == accountID {
                return transaction.destinationAmount ?? transaction.amount
            }
            return 0
        }
    }

    /// Per-currency totals of accounts with `includeInNetWorth`. Hidden accounts are included. Deleted ones are not.
    /// Counts every transaction, Upcoming ones included; current net wealth is
    /// `AccountBalance.currentNetWorth(in:today:)` (D21).
    public static func netWorth(in snapshot: LedgerSnapshot) throws -> [String: Decimal] {
        var totals: [String: Decimal] = [:]
        for account in snapshot.accounts where account.deletedAt == nil && account.includeInNetWorth {
            let balance = try balance(of: account.id, in: snapshot)
            totals[account.currencyCode, default: 0] += balance
        }
        return totals
    }

    public static func savingAccount(
        _ account: Account,
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> LedgerSnapshot {
        var snapshot = snapshot
        var account = normalize(account)
        try validate(account, in: snapshot)
        if let existing = snapshot.accounts.first(where: { $0.id == account.id }) {
            let currencyChanged = existing.currencyCode != account.currencyCode
            let hasTransactions = snapshot.transactions.contains { transaction in
                transaction.deletedAt == nil
                    && (transaction.accountID == account.id || transaction.transferAccountID == account.id)
            }
            // Any stored scheduled item, Completed or hidden ones included, keeps its accounts' currency too, so
            // a form opened before the item was scheduled can't change it (D410.1, D412).
            let isScheduled = CurrencyLock.scheduledAccountIDs(in: snapshot).contains(account.id)
            if currencyChanged && (hasTransactions || isScheduled) {
                throw LedgerValidationError.currencyLocked
            }
            account.createdAt = existing.createdAt
            account.updatedAt = now
            replace(&snapshot.accounts, with: account)
        } else {
            snapshot.accounts.append(account)
        }
        return snapshot
    }

    /// Deletes the account with every transaction in or out of it. Refunds elsewhere of an expense that goes
    /// with it are unlinked and keep their category (D19).
    public static func deletingAccount(id: UUID, in snapshot: LedgerSnapshot, now: Date) throws -> LedgerSnapshot {
        guard snapshot.accounts.contains(where: { $0.id == id }) else {
            throw LedgerValidationError.unknownAccount
        }
        var snapshot = snapshot
        let removed = Set(
            snapshot.transactions.compactMap { transaction -> UUID? in
                if transaction.accountID == id || transaction.transferAccountID == id {
                    return transaction.id
                }
                return nil
            }
        )
        snapshot.transactions.removeAll { removed.contains($0.id) }
        unlinkRefunds(of: removed, in: &snapshot, now: now)
        snapshot.splits.removeAll { split in
            guard let transactionID = split.transactionID else {
                return false
            }
            return removed.contains(transactionID)
        }
        snapshot.attachments.removeAll { attachment in
            guard let transactionID = attachment.transactionID else {
                return false
            }
            return removed.contains(transactionID)
        }
        snapshot.accounts.removeAll { $0.id == id }
        return snapshot
    }

    public static func savingTransaction(
        _ transaction: Transaction,
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> LedgerSnapshot {
        var index = LedgerIndex(snapshot)
        try savingTransaction(transaction, in: &index, now: now)
        return index.snapshot
    }

    /// The one save of a transaction, on an index (#285): a single save builds one, and a batch keeps one for all
    /// its rows. If it throws, `index` is unchanged.
    static func savingTransaction(_ transaction: Transaction, in index: inout LedgerIndex, now: Date) throws {
        var transaction = normalize(transaction)
        var keptZoneID: String?
        if let position = index.position(of: transaction.id) {
            let existing = index.snapshot.transactions[position]
            // An edit keeps the stored zone ID as it is, even one this device doesn't recognise, such as one a
            // backup restored; its day reads as UTC (`TransactionCalendar.storedTimeZone`, D230).
            if transaction.timeZoneID == LedgerText.trimmed(existing.timeZoneID) {
                transaction.timeZoneID = existing.timeZoneID
                keptZoneID = existing.timeZoneID
            }
            // Validation only. The schema stores `type` as a plain string and does not
            // constrain it. #37 will allow converting a transaction to a transfer.
            let crossesTransfer = (existing.type == .transfer) != (transaction.type == .transfer)
            if crossesTransfer {
                throw LedgerValidationError.transactionTypeChangeNotAllowed
            }
            transaction.createdAt = existing.createdAt
            transaction.updatedAt = now
        }
        try validate(transaction, in: index, keepingZoneID: keptZoneID)
        touchPayee(for: transaction, in: &index, now: now)
        index.replaceOrAppend(transaction)
        applyingOriginal(transaction, to: &index, now: now)
    }

    /// Changes a transaction that's already stored, as `savingTransaction(_:in:now:)` does. One that isn't stored,
    /// because it was deleted while an Edit form was open, say in another window, throws `missingTransaction` and
    /// changes nothing: an edit never adds the transaction back as a new one (#264). A transfer is one record for
    /// both accounts, so deleting either side, or either account, deletes it, and its edit is refused too.
    public static func updatingTransaction(
        _ transaction: Transaction,
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> LedgerSnapshot {
        var index = LedgerIndex(snapshot)
        try updatingTransaction(transaction, in: &index, now: now)
        return index.snapshot
    }

    /// `updatingTransaction(_:in:now:)` on an index, for a single edit and for each row of a batch (#285).
    static func updatingTransaction(_ transaction: Transaction, in index: inout LedgerIndex, now: Date) throws {
        guard index.liveTransaction(transaction.id) != nil else {
            throw LedgerValidationError.missingTransaction
        }
        try savingTransaction(transaction, in: &index, now: now)
    }

    /// Deletes the transaction with its splits and attachments. Its refunds stay, unlinked, with `isRefund`
    /// and their category: 'Refund (original deleted)' (D19).
    public static func deletingTransaction(id: UUID, in snapshot: LedgerSnapshot, now: Date) throws -> LedgerSnapshot {
        guard snapshot.transactions.contains(where: { $0.id == id }) else {
            throw LedgerValidationError.missingTransaction
        }
        var snapshot = snapshot
        snapshot.transactions.removeAll { $0.id == id }
        unlinkRefunds(of: [id], in: &snapshot, now: now)
        snapshot.splits.removeAll { $0.transactionID == id }
        snapshot.attachments.removeAll { $0.transactionID == id }
        return snapshot
    }

    /// Saves a batch of new transactions in one pass (#30 import, S35). It gives the same result and the same
    /// errors as calling `savingTransaction` for each in turn, without copying and scanning the whole ledger
    /// once per transaction.
    ///
    /// The one-pass path applies when every transaction is new (its id isn't stored or repeated) and unlinked
    /// (no `refundOfID`). Such a transaction has no splits and no linked refunds yet, so it's validated against
    /// the accounts, categories, payees and tags alone. Any other batch is saved one by one.
    public static func savingNewTransactions(
        _ transactions: [Transaction],
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> LedgerSnapshot {
        var stored = Set(snapshot.transactions.map(\.id))
        let isNewAndUnlinked = transactions.allSatisfy { stored.insert($0.id).inserted && $0.refundOfID == nil }
        guard isNewAndUnlinked else {
            return try transactions.reduce(snapshot) { try savingTransaction($1, in: $0, now: now) }
        }
        var reference = snapshot
        reference.transactions = []
        reference.splits = []
        // One index for the whole batch: the reference doesn't change while the rows are checked (#285).
        let index = LedgerIndex(reference)
        var payees = LedgerIndex(LedgerSnapshot(payees: snapshot.payees))
        var result = snapshot
        result.transactions.reserveCapacity(snapshot.transactions.count + transactions.count)
        for transaction in transactions {
            let transaction = normalize(transaction)
            try validate(transaction, in: index)
            touchPayee(for: transaction, in: &payees, now: now)
            result.transactions.append(transaction)
        }
        result.payees = payees.snapshot.payees
        return result
    }

    /// Deletes a batch of transactions in one pass, with their splits and attachments, and unlinks their
    /// refunds: the same as `deletingTransaction` for each (D19). Throws `missingTransaction`, changing
    /// nothing, if any isn't stored.
    public static func deletingTransactions(
        ids: [UUID],
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> LedgerSnapshot {
        let doomed = Set(ids)
        let found = snapshot.transactions.reduce(into: 0) { count, transaction in
            if doomed.contains(transaction.id) { count += 1 }
        }
        guard found == doomed.count else {
            throw LedgerValidationError.missingTransaction
        }
        var snapshot = snapshot
        snapshot.transactions.removeAll { doomed.contains($0.id) }
        unlinkRefunds(of: doomed, in: &snapshot, now: now)
        snapshot.splits.removeAll { $0.transactionID.map(doomed.contains) == true }
        snapshot.attachments.removeAll { $0.transactionID.map(doomed.contains) == true }
        return snapshot
    }

    private static func touchPayee(for transaction: Transaction, in index: inout LedgerIndex, now: Date) {
        guard transaction.deletedAt == nil, transaction.type != .transfer, let payeeID = transaction.payeeID else {
            return
        }
        index.updatePayee(payeeID) { payee in
            payee.lastUsedAt = transaction.date
            if transaction.categoryID != nil {
                payee.defaultCategoryID = transaction.categoryID
            }
            payee.updatedAt = now
        }
    }

    static func replace<T: Identifiable>(_ items: inout [T], with item: T) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        }
    }

    static func replaceOrAppend<T: Identifiable>(_ items: inout [T], with item: T) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }
}
