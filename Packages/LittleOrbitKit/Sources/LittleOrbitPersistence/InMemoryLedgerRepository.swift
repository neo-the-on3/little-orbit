import Foundation
import LittleOrbitDomain

/// Process-local ledger. Used on Linux and in tests. It applies the same `LedgerBook` rules as the SwiftData store.
@MainActor
public final class InMemoryLedgerRepository: LedgerRepository {
    private var snapshot = LedgerSnapshot()
    /// The pending-seed marker as a flag (D293): a new in-memory store is a brand-new store, so it starts pending.
    public private(set) var isDefaultSeedPending: Bool
    private let now: @MainActor () -> Date

    /// `seedPending: false` stands in for an existing install, whose store has no pending marker.
    public init(now: @escaping @MainActor () -> Date = { Date() }, seedPending: Bool = true) {
        self.now = now
        self.isDefaultSeedPending = seedPending
    }

    public func markDefaultSeedDone() {
        isDefaultSeedPending = false
    }

    public func accounts() throws -> [Account] {
        snapshot.accountsVisible()
    }

    public func saveAccount(_ account: Account) throws {
        snapshot = try LedgerBook.savingAccount(account, in: snapshot, now: now())
    }

    public func deleteAccount(id: UUID) throws {
        snapshot = try LedgerBook.deletingAccount(id: id, in: snapshot, now: now())
    }

    public func transactions() throws -> [Transaction] {
        snapshot.transactionsVisible()
    }

    public func saveTransaction(_ transaction: Transaction) throws {
        snapshot = try LedgerBook.savingTransaction(transaction, in: snapshot, now: now())
    }

    public func deleteTransaction(id: UUID) throws {
        snapshot = try LedgerBook.deletingTransaction(id: id, in: snapshot, now: now())
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

    public func mergeCategories(_ sourceID: UUID, into survivingID: UUID) throws {
        snapshot = try LedgerBook.mergingCategories(sourceID, into: survivingID, in: snapshot, now: now())
    }

    public func archiveCategory(id: UUID, archived: Bool) throws {
        snapshot = try LedgerBook.archivingCategory(id: id, archived: archived, in: snapshot, now: now())
    }

    public func reorderCategories(_ orderedIDs: [UUID]) throws {
        snapshot = try LedgerBook.reorderingCategories(orderedIDs, in: snapshot, now: now())
    }

    public func seedDefaultCategories(names: any DefaultCategoryNaming) throws {
        snapshot = LedgerBook.seedDefaultCategories(names: names, in: snapshot, now: now())
    }

    public func payees() throws -> [Payee] {
        snapshot.payeesVisible()
    }

    public func savePayee(_ payee: Payee) throws {
        snapshot = try LedgerBook.savingPayee(payee, in: snapshot, now: now())
    }

    public func payeeReferenceCount(_ payeeID: UUID) throws -> Int {
        snapshot.payeeReferenceCount(payeeID)
    }

    public func recordNames(categoryIDs: Set<UUID>, payeeIDs: Set<UUID>) throws -> [UUID: String] {
        snapshot.recordNames(categoryIDs: categoryIDs, payeeIDs: payeeIDs)
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

    public func balance(of accountID: UUID, today: CalendarDay) throws -> Decimal {
        try AccountBalance.current(of: accountID, in: snapshot, today: today)
    }

    public func netWorth(today: CalendarDay) throws -> [String: Decimal] {
        try AccountBalance.currentNetWorth(in: snapshot, today: today)
    }

    public func atomically<T>(_ body: () throws -> T) throws -> T {
        let saved = snapshot
        do {
            return try body()
        } catch {
            snapshot = saved
            throw error
        }
    }
}

/// Backups (#40): the whole ledger out, and replaced at once.
extension InMemoryLedgerRepository: LedgerBackupSource {
    public func ledgerSnapshot() throws -> LedgerSnapshot {
        snapshot
    }

    /// A completed restore marks the seeding done, so even an empty backup never leads to a seed (D293.2).
    /// Budgets and scheduled items are checked first by the rules the SwiftData store uses, so the two never keep
    /// different data (`LedgerBook.validateStoredBudgets`, #174 B1; `LedgerBook.validateStoredScheduledItems`, #26);
    /// nothing changes when either throws.
    public func replaceLedger(with snapshot: LedgerSnapshot) throws {
        try LedgerBook.validateStoredBudgets(in: snapshot)
        try LedgerBook.validateStoredScheduledItems(in: snapshot)
        self.snapshot = snapshot
        markDefaultSeedDone()
    }
}

/// Budgets (#25), through the same `LedgerBook` rules as the SwiftData store.
extension InMemoryLedgerRepository: BudgetRepository {
    public func budgets() throws -> [Budget] {
        snapshot.budgetsVisible()
    }

    public func saveBudget(_ budget: Budget) throws {
        snapshot = try LedgerBook.savingBudget(budget, in: snapshot, now: now())
    }

    public func changeBudgetLimit(
        of budgetID: UUID,
        to amount: Decimal,
        fromPeriodStartingOn periodStart: CalendarDay,
    ) throws {
        snapshot = try LedgerBook.changingBudgetLimit(
            of: budgetID,
            to: amount,
            fromPeriodStartingOn: periodStart,
            in: snapshot,
            now: now(),
        )
    }

    public func deleteBudget(id: UUID) throws {
        snapshot = try LedgerBook.deletingBudget(id: id, in: snapshot)
    }

    public func budgetLedger() throws -> LedgerSnapshot {
        snapshot
    }
}

/// Scheduled items (#26), through the same `LedgerBook` rules as the SwiftData store. Each call replaces the
/// snapshot once, so an occurrence's transaction and its settled record go in together.
extension InMemoryLedgerRepository: ScheduleRepository {
    public func scheduleLedger() throws -> LedgerSnapshot {
        snapshot
    }

    public func saveScheduledItem(_ item: ScheduledItem, today: CalendarDay, now: Date) throws {
        snapshot = try LedgerBook.savingScheduledItem(item, in: snapshot, today: today, now: now)
    }

    public func deleteScheduledItem(id: UUID) throws {
        snapshot = try LedgerBook.deletingScheduledItem(id: id, in: snapshot)
    }

    public func settleScheduledOccurrence(_ settlement: ScheduledSettlement) throws -> Transaction? {
        let outcome = try LedgerBook.settlingScheduledOccurrence(settlement, in: snapshot, now: now())
        snapshot = outcome.snapshot
        return outcome.transaction
    }

    public func catchUpScheduledItems(today: CalendarDay, pruningOrphans: Bool) throws -> ScheduledCatchUp {
        let outcome = LedgerBook.catchingUpScheduledItems(
            in: snapshot,
            today: today,
            now: now(),
            pruningOrphans: pruningOrphans,
        )
        snapshot = outcome.snapshot
        return outcome.result
    }
}
