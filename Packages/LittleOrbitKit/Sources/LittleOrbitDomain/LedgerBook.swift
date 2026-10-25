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
            if currencyChanged && hasTransactions {
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
        var snapshot = snapshot
        var transaction = normalize(transaction)
        var keptZoneID: String?
        if let existing = snapshot.transactions.first(where: { $0.id == transaction.id }) {
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
        try validate(transaction, in: snapshot, keepingZoneID: keptZoneID)
        touchPayee(for: transaction, in: &snapshot, now: now)
        replaceOrAppend(&snapshot.transactions, with: transaction)
        applyingOriginal(transaction, to: &snapshot, now: now)
        return snapshot
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

    private static func touchPayee(
        for transaction: Transaction,
        in snapshot: inout LedgerSnapshot,
        now: Date,
    ) {
        guard transaction.deletedAt == nil, transaction.type != .transfer, let payeeID = transaction.payeeID else {
            return
        }
        guard let index = snapshot.payees.firstIndex(where: { $0.id == payeeID && $0.deletedAt == nil }) else {
            return
        }
        snapshot.payees[index].lastUsedAt = transaction.date
        if transaction.categoryID != nil {
            snapshot.payees[index].defaultCategoryID = transaction.categoryID
        }
        snapshot.payees[index].updatedAt = now
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
