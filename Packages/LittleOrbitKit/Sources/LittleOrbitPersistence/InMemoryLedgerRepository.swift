import Foundation
import LittleOrbitDomain

/// Process-local ledger. Used on Linux and in tests. It applies the same `LedgerBook` rules as the SwiftData store.
@MainActor
public final class InMemoryLedgerRepository: LedgerRepository {
    private var snapshot = LedgerSnapshot()
    private let now: @MainActor () -> Date

    public init(now: @escaping @MainActor () -> Date = { Date() }) {
        self.now = now
    }

    public func accounts() throws -> [Account] {
        snapshot.accountsVisible()
    }

    public func saveAccount(_ account: Account) throws {
        snapshot = try LedgerBook.savingAccount(account, in: snapshot, now: now())
    }

    public func deleteAccount(id: UUID) throws {
        snapshot = try LedgerBook.deletingAccount(id: id, in: snapshot)
    }

    public func transactions() throws -> [Transaction] {
        snapshot.transactionsVisible()
    }

    public func saveTransaction(_ transaction: Transaction) throws {
        snapshot = try LedgerBook.savingTransaction(transaction, in: snapshot, now: now())
    }

    public func deleteTransaction(id: UUID) throws {
        snapshot = try LedgerBook.deletingTransaction(id: id, in: snapshot)
    }

    public func recordScheduledOccurrence(_ transaction: Transaction) throws -> Transaction {
        let result = try LedgerBook.recordScheduledOccurrence(transaction, in: snapshot, now: now())
        snapshot = result.snapshot
        return result.transaction
    }

    public func categories() throws -> [TransactionCategory] {
        snapshot.categoriesVisible()
    }

    public func saveCategory(_ category: TransactionCategory) throws {
        snapshot = try LedgerBook.savingCategory(category, in: snapshot, now: now())
    }

    public func deleteCategory(id: UUID, reassigningTo categoryID: UUID?) throws {
        snapshot = try LedgerBook.deletingCategory(id: id, reassigningTo: categoryID, in: snapshot, now: now())
    }

    public func seedDefaultCategories() throws {
        snapshot = LedgerBook.seedDefaultCategories(in: snapshot, now: now())
    }

    public func payees() throws -> [Payee] {
        snapshot.payeesVisible()
    }

    public func savePayee(_ payee: Payee) throws {
        snapshot = try LedgerBook.savingPayee(payee, in: snapshot, now: now())
    }

    public func deletePayee(id: UUID) throws {
        snapshot = try LedgerBook.deletingPayee(id: id, in: snapshot, now: now())
    }

    public func mergePayees(_ sourceID: UUID, into survivingID: UUID) throws {
        snapshot = try LedgerBook.mergingPayees(sourceID, into: survivingID, in: snapshot, now: now())
    }

    public func tags() throws -> [Tag] {
        snapshot.tagsVisible()
    }

    public func saveTag(_ tag: Tag) throws {
        snapshot = try LedgerBook.savingTag(tag, in: snapshot, now: now())
    }

    public func deleteTag(id: UUID) throws {
        snapshot = try LedgerBook.deletingTag(id: id, in: snapshot, now: now())
    }

    public func splits(for transactionID: UUID?) throws -> [TransactionSplit] {
        snapshot.splitsVisible(for: transactionID)
    }

    public func replaceSplits(_ splits: [TransactionSplit], for transactionID: UUID) throws {
        snapshot = try LedgerBook.replacingSplits(splits, for: transactionID, in: snapshot, now: now())
    }

    public func attachments(for transactionID: UUID?) throws -> [Attachment] {
        snapshot.attachmentsVisible(for: transactionID)
    }

    public func saveAttachment(_ attachment: Attachment) throws {
        snapshot = try LedgerBook.savingAttachment(attachment, in: snapshot, now: now())
    }

    public func deleteAttachment(id: UUID) throws {
        snapshot = try LedgerBook.deletingAttachment(id: id, in: snapshot)
    }

    public func balance(of accountID: UUID) throws -> Decimal {
        try LedgerBook.balance(of: accountID, in: snapshot)
    }

    public func netWorth() throws -> [String: Decimal] {
        try LedgerBook.netWorth(in: snapshot)
    }
}

/// Backups (#40): the whole ledger out, and replaced at once.
extension InMemoryLedgerRepository: LedgerBackupSource {
    public func ledgerSnapshot() throws -> LedgerSnapshot {
        snapshot
    }

    public func replaceLedger(with snapshot: LedgerSnapshot) throws {
        self.snapshot = snapshot
    }
}
