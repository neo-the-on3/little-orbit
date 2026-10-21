import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence

/// An in-memory repository whose account and transaction reads can be made to fail, for the edit form's
/// fail-closed tests.
@MainActor
final class UnreadableAccountsRepository: LedgerRepository {
    struct ReadFailure: Error {}

    let base: InMemoryLedgerRepository
    var failsReads = false

    init(_ base: InMemoryLedgerRepository) {
        self.base = base
    }

    func accounts() throws -> [Account] {
        if failsReads {
            throw ReadFailure()
        }
        return try base.accounts()
    }

    func saveAccount(_ account: Account) throws { try base.saveAccount(account) }
    func deleteAccount(id: UUID) throws { try base.deleteAccount(id: id) }

    func transactions() throws -> [Transaction] {
        if failsReads {
            throw ReadFailure()
        }
        return try base.transactions()
    }

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
    func seedDefaultCategories() throws { try base.seedDefaultCategories() }

    func payees() throws -> [Payee] { try base.payees() }
    func savePayee(_ payee: Payee) throws { try base.savePayee(payee) }
    func deletePayee(id: UUID) throws { try base.deletePayee(id: id) }
    func mergePayees(_ sourceID: UUID, into survivingID: UUID) throws {
        try base.mergePayees(sourceID, into: survivingID)
    }

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
}
