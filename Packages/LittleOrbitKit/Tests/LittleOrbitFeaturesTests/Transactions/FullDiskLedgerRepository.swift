import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence

/// The in-memory store whose writes fail with the system's full-disk error while `isFull` is set, for X8 and
/// X8a (D191.3): the real use cases run, and `atomically` rolls back what a change wrote before the failure.
@MainActor
final class FullDiskLedgerRepository: LedgerRepository {
    let base: InMemoryLedgerRepository
    var isFull = false

    init(_ base: InMemoryLedgerRepository) {
        self.base = base
    }

    private func write() throws {
        if isFull {
            throw CocoaError(.fileWriteOutOfSpace)
        }
    }

    func accounts() throws -> [Account] { try base.accounts() }
    func saveAccount(_ account: Account) throws {
        try write()
        try base.saveAccount(account)
    }
    func deleteAccount(id: UUID) throws {
        try write()
        try base.deleteAccount(id: id)
    }

    func transactions() throws -> [Transaction] { try base.transactions() }
    func saveTransaction(_ transaction: Transaction) throws {
        try write()
        try base.saveTransaction(transaction)
    }
    func deleteTransaction(id: UUID) throws {
        try write()
        try base.deleteTransaction(id: id)
    }
    func recordScheduledOccurrence(_ transaction: Transaction) throws -> Transaction {
        try write()
        return try base.recordScheduledOccurrence(transaction)
    }

    func categories() throws -> [TransactionCategory] { try base.categories() }
    func saveCategory(_ category: TransactionCategory) throws {
        try write()
        try base.saveCategory(category)
    }
    func deleteCategory(id: UUID, reassigningTo categoryID: UUID?) throws {
        try write()
        try base.deleteCategory(id: id, reassigningTo: categoryID)
    }
    func seedDefaultCategories() throws { try base.seedDefaultCategories() }

    func payees() throws -> [Payee] { try base.payees() }
    func savePayee(_ payee: Payee) throws {
        try write()
        try base.savePayee(payee)
    }
    func deletePayee(id: UUID) throws {
        try write()
        try base.deletePayee(id: id)
    }
    func mergePayees(_ sourceID: UUID, into survivingID: UUID) throws {
        try write()
        try base.mergePayees(sourceID, into: survivingID)
    }

    func tags() throws -> [Tag] { try base.tags() }
    func saveTag(_ tag: Tag) throws {
        try write()
        try base.saveTag(tag)
    }
    func deleteTag(id: UUID) throws {
        try write()
        try base.deleteTag(id: id)
    }

    func splits(for transactionID: UUID?) throws -> [TransactionSplit] { try base.splits(for: transactionID) }
    func replaceSplits(_ splits: [TransactionSplit], for transactionID: UUID) throws {
        try write()
        try base.replaceSplits(splits, for: transactionID)
    }

    func attachments(for transactionID: UUID?) throws -> [Attachment] { try base.attachments(for: transactionID) }
    func saveAttachment(_ attachment: Attachment) throws {
        try write()
        try base.saveAttachment(attachment)
    }
    func deleteAttachment(id: UUID) throws {
        try write()
        try base.deleteAttachment(id: id)
    }

    func balance(of accountID: UUID, today: CalendarDay) throws -> Decimal {
        try base.balance(of: accountID, today: today)
    }
    func netWorth(today: CalendarDay) throws -> [String: Decimal] { try base.netWorth(today: today) }
    func atomically<T>(_ body: () throws -> T) throws -> T { try base.atomically(body) }
}
