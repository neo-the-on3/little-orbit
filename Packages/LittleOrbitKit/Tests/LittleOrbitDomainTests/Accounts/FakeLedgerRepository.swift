import Foundation
import LittleOrbitDomain

/// A fake `LedgerRepository` for the use-case tests: accounts, transactions, categories, payees, splits and
/// attachments in memory, through the same `LedgerBook` rules as the real stores. The rest of the port isn't
/// used by the use cases and throws. `failsAfterWrites` makes a write fail partway through a change, and
/// `atomically` restores the snapshot like the real stores do.
@MainActor
final class FakeLedgerRepository: LedgerRepository {
    struct Unsupported: Error {}
    struct ReadFailure: Error {}
    struct WriteFailure: Error {}

    private(set) var snapshot = LedgerSnapshot()
    private(set) var savedAccountIDs: [UUID] = []
    var failsReads = false
    /// When set, transaction, split, attachment, category and payee-merge writes after this many fail.
    var failsAfterWrites: Int?
    private(set) var writes = 0
    private(set) var atomicChanges = 0
    private var tick = 0.0

    init(accounts: [Account] = [], categories: [TransactionCategory] = [], transactions: [Transaction] = []) throws {
        for account in accounts {
            try saveAccount(account)
        }
        for category in categories {
            snapshot = try LedgerBook.savingCategory(category, in: snapshot, now: now())
        }
        for transaction in transactions {
            snapshot = try LedgerBook.savingTransaction(transaction, in: snapshot, now: now())
        }
        savedAccountIDs = []
    }

    private func write() throws {
        if let limit = failsAfterWrites, writes >= limit {
            throw WriteFailure()
        }
        writes += 1
    }

    func atomically<T>(_ body: () throws -> T) throws -> T {
        atomicChanges += 1
        let saved = snapshot
        do {
            return try body()
        } catch {
            snapshot = saved
            throw error
        }
    }

    private func now() -> Date {
        tick += 1
        return Date(timeIntervalSince1970: tick)
    }

    func accounts() throws -> [Account] {
        if failsReads {
            throw ReadFailure()
        }
        return snapshot.accountsVisible()
    }

    func saveAccount(_ account: Account) throws {
        snapshot = try LedgerBook.savingAccount(account, in: snapshot, now: now())
        savedAccountIDs.append(account.id)
    }

    func deleteAccount(id: UUID) throws {
        snapshot = try LedgerBook.deletingAccount(id: id, in: snapshot, now: now())
    }

    func transactions() throws -> [Transaction] {
        if failsReads {
            throw ReadFailure()
        }
        return snapshot.transactionsVisible()
    }

    func saveTransaction(_ transaction: Transaction) throws {
        try write()
        snapshot = try LedgerBook.savingTransaction(transaction, in: snapshot, now: now())
    }

    func deleteTransaction(id: UUID) throws {
        try write()
        snapshot = try LedgerBook.deletingTransaction(id: id, in: snapshot, now: now())
    }

    func recordScheduledOccurrence(_ transaction: Transaction) throws -> Transaction { throw Unsupported() }
    func categories() throws -> [TransactionCategory] { snapshot.categoriesVisible() }
    func saveCategory(_ category: TransactionCategory) throws {
        try write()
        snapshot = try LedgerBook.savingCategory(category, in: snapshot, now: now())
    }
    func deleteCategory(id: UUID, reassigningTo categoryID: UUID?) throws {
        try write()
        snapshot = try LedgerBook.deletingCategory(id: id, reassigningTo: categoryID, in: snapshot, now: now())
    }
    func mergeCategories(_ sourceID: UUID, into survivingID: UUID) throws {
        try write()
        snapshot = try LedgerBook.mergingCategories(sourceID, into: survivingID, in: snapshot, now: now())
    }
    func archiveCategory(id: UUID, archived: Bool) throws {
        try write()
        snapshot = try LedgerBook.archivingCategory(id: id, archived: archived, in: snapshot, now: now())
    }
    func reorderCategories(_ orderedIDs: [UUID]) throws {
        try write()
        snapshot = try LedgerBook.reorderingCategories(orderedIDs, in: snapshot, now: now())
    }
    func seedDefaultCategories(names: any DefaultCategoryNaming) throws {
        snapshot = LedgerBook.seedDefaultCategories(names: names, in: snapshot, now: now())
    }
    func payees() throws -> [Payee] { snapshot.payeesVisible() }
    func savePayee(_ payee: Payee) throws { snapshot = try LedgerBook.savingPayee(payee, in: snapshot, now: now()) }
    func payeeReferenceCount(_ payeeID: UUID) throws -> Int { snapshot.payeeReferenceCount(payeeID) }
    func deletePayee(id: UUID) throws {
        try write()
        snapshot = try LedgerBook.deletingPayee(id: id, in: snapshot, now: now())
    }
    func mergePayees(_ sourceID: UUID, into survivingID: UUID) throws {
        try write()
        snapshot = try LedgerBook.mergingPayees(sourceID, into: survivingID, in: snapshot, now: now())
    }
    func tags() throws -> [Tag] { throw Unsupported() }
    func saveTag(_ tag: Tag) throws { throw Unsupported() }
    func deleteTag(id: UUID) throws { throw Unsupported() }
    func splits(for transactionID: UUID?) throws -> [TransactionSplit] { snapshot.splitsVisible(for: transactionID) }
    func replaceSplits(_ splits: [TransactionSplit], for transactionID: UUID) throws {
        try write()
        snapshot = try LedgerBook.replacingSplits(splits, for: transactionID, in: snapshot, now: now())
    }
    func attachments(for transactionID: UUID?) throws -> [Attachment] {
        snapshot.attachmentsVisible(for: transactionID)
    }
    func saveAttachment(_ attachment: Attachment) throws {
        try write()
        snapshot = try LedgerBook.savingAttachment(attachment, in: snapshot, now: now())
    }
    func deleteAttachment(id: UUID) throws { throw Unsupported() }
    func balance(of accountID: UUID, today: CalendarDay) throws -> Decimal {
        try AccountBalance.current(of: accountID, in: snapshot, today: today)
    }
    func netWorth(today: CalendarDay) throws -> [String: Decimal] {
        try AccountBalance.currentNetWorth(in: snapshot, today: today)
    }
}
