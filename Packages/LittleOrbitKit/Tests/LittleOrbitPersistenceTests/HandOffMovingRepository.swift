import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence

/// The in-memory store, saving batches off the main actor, where the store moves at the hand-off (#285, B; Tech
/// Architect's review 5667872455, m1): for each of the first `moves` calls, `writeBatchOffMain` runs `move`, a
/// write landing just as the batch is handed off, and returns `false` with nothing written, as a store whose
/// revision moved does. After that it hands off to the in-memory store. Every other call goes to `base`.
@MainActor
final class HandOffMovingRepository: LedgerRepository {
    let base: InMemoryLedgerRepository
    /// How many hand-offs still find the store moved.
    var moves: Int
    /// The write that lands at each moved hand-off; by default one that changes nothing but the revision.
    var move: (InMemoryLedgerRepository) throws -> Void = { try $0.writeBatch($0.ledgerSnapshot()) }
    /// Every `writeBatchOffMain` call, moved or not.
    private(set) var handOffs = 0

    init(_ base: InMemoryLedgerRepository, moves: Int) {
        self.base = base
        self.moves = moves
        base.offMainSave = {}
    }

    var savesBatchesOffMain: Bool { true }

    func writeBatchOffMain(_ snapshot: LedgerSnapshot, expectedRevision: UInt64) async throws -> Bool {
        handOffs += 1
        guard moves <= 0 else {
            moves -= 1
            try move(base)
            return false
        }
        return try await base.writeBatchOffMain(snapshot, expectedRevision: expectedRevision)
    }

    var revision: UInt64? { base.revision }
    func batchBase() throws -> LedgerBatchBase { try base.batchBase() }
    func writeBatch(_ snapshot: LedgerSnapshot) throws { try base.writeBatch(snapshot) }
    func atomically<T>(_ body: () throws -> T) throws -> T { try base.atomically(body) }

    var isDefaultSeedPending: Bool { base.isDefaultSeedPending }
    func markDefaultSeedDone() { base.markDefaultSeedDone() }

    func accounts() throws -> [Account] { try base.accounts() }
    func saveAccount(_ account: Account) throws { try base.saveAccount(account) }
    func deleteAccount(id: UUID) throws { try base.deleteAccount(id: id) }

    func transactions() throws -> [Transaction] { try base.transactions() }
    func saveTransaction(_ transaction: Transaction) throws { try base.saveTransaction(transaction) }
    func updateTransaction(_ transaction: Transaction) throws { try base.updateTransaction(transaction) }
    func deleteTransaction(id: UUID) throws { try base.deleteTransaction(id: id) }
    func saveNewTransactions(_ transactions: [Transaction]) throws { try base.saveNewTransactions(transactions) }
    func deleteTransactions(ids: [UUID]) throws { try base.deleteTransactions(ids: ids) }

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
    func seedDefaultCategories(names: any DefaultCategoryNaming) throws { try base.seedDefaultCategories(names: names) }

    func payees() throws -> [Payee] { try base.payees() }
    func savePayee(_ payee: Payee) throws { try base.savePayee(payee) }
    func deletePayee(id: UUID) throws { try base.deletePayee(id: id) }
    func mergePayees(_ sourceID: UUID, into survivingID: UUID) throws {
        try base.mergePayees(sourceID, into: survivingID)
    }
    func payeeReferenceCount(_ payeeID: UUID) throws -> Int { try base.payeeReferenceCount(payeeID) }
    func payeesInUse(among ids: Set<UUID>) throws -> Set<UUID> { try base.payeesInUse(among: ids) }
    func deletePayees(ids: [UUID]) throws { try base.deletePayees(ids: ids) }

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
