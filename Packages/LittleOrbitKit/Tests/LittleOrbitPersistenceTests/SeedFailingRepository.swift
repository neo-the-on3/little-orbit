import Foundation
import LittleOrbitDomain

/// Wraps a store so the seed save can fail, as a full disk would, while everything else, the pending-seed marker
/// included, is the real store's (D293).
@MainActor
final class SeedFailingRepository: LedgerRepository {
    struct SeedFailure: Error {}

    let base: any LedgerRepository
    var failsSeed = true

    init(_ base: any LedgerRepository) {
        self.base = base
    }

    func seedDefaultCategories(names: any DefaultCategoryNaming) throws {
        if failsSeed {
            throw SeedFailure()
        }
        try base.seedDefaultCategories(names: names)
    }

    var isDefaultSeedPending: Bool { base.isDefaultSeedPending }
    func markDefaultSeedDone() { base.markDefaultSeedDone() }

    func accounts() throws -> [Account] { try base.accounts() }
    func saveAccount(_ account: Account) throws { try base.saveAccount(account) }
    func deleteAccount(id: UUID) throws { try base.deleteAccount(id: id) }
    func transactions() throws -> [Transaction] { try base.transactions() }
    func saveTransaction(_ transaction: Transaction) throws { try base.saveTransaction(transaction) }
    func deleteTransaction(id: UUID) throws { try base.deleteTransaction(id: id) }
    func recordScheduledOccurrence(_ transaction: Transaction) throws -> Transaction {
        try base.recordScheduledOccurrence(transaction)
    }
    func categories() throws -> [TransactionCategory] { try base.categories() }
    func saveCategory(_ category: TransactionCategory) throws { try base.saveCategory(category) }
    func deleteCategory(id: UUID, reassigningTo categoryID: UUID?) throws {
        try base.deleteCategory(id: id, reassigningTo: categoryID)
    }
    func mergeCategories(_ sourceID: UUID, into survivingID: UUID) throws {
        try base.mergeCategories(sourceID, into: survivingID)
    }
    func archiveCategory(id: UUID, archived: Bool) throws { try base.archiveCategory(id: id, archived: archived) }
    func reorderCategories(_ orderedIDs: [UUID]) throws { try base.reorderCategories(orderedIDs) }
    func payees() throws -> [Payee] { try base.payees() }
    func savePayee(_ payee: Payee) throws { try base.savePayee(payee) }
    func deletePayee(id: UUID) throws { try base.deletePayee(id: id) }
    func mergePayees(_ sourceID: UUID, into survivingID: UUID) throws {
        try base.mergePayees(sourceID, into: survivingID)
    }
    func payeeReferenceCount(_ payeeID: UUID) throws -> Int { try base.payeeReferenceCount(payeeID) }
    func tags() throws -> [Tag] { try base.tags() }
    func saveTag(_ tag: Tag) throws { try base.saveTag(tag) }
    func deleteTag(id: UUID) throws { try base.deleteTag(id: id) }
    func splits(for transactionID: UUID?) throws -> [TransactionSplit] { try base.splits(for: transactionID) }
    func replaceSplits(_ splits: [TransactionSplit], for transactionID: UUID) throws {
        try base.replaceSplits(splits, for: transactionID)
    }
    func attachments(for transactionID: UUID?) throws -> [Attachment] { try base.attachments(for: transactionID) }
    func saveAttachment(_ attachment: Attachment) throws { try base.saveAttachment(attachment) }
    func deleteAttachment(id: UUID) throws { try base.deleteAttachment(id: id) }
    func balance(of accountID: UUID, today: CalendarDay) throws -> Decimal {
        try base.balance(of: accountID, today: today)
    }
    func netWorth(today: CalendarDay) throws -> [String: Decimal] { try base.netWorth(today: today) }
    func atomically<T>(_ body: () throws -> T) throws -> T { try base.atomically(body) }
}
