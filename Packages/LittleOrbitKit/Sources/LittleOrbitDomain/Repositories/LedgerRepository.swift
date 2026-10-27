import Foundation

/// The storage port that the use cases depend on. It lives in Domain so nothing above Domain needs Persistence.
///
/// `LittleOrbitPersistence` implements it: the in-memory store works everywhere, SwiftData is the on-device store.
@MainActor
public protocol LedgerRepository: AnyObject {
    func accounts() throws -> [Account]
    func saveAccount(_ account: Account) throws
    func deleteAccount(id: UUID) throws

    func transactions() throws -> [Transaction]
    func saveTransaction(_ transaction: Transaction) throws
    /// See `LedgerBook.updatingTransaction(_:in:now:)`: an edit of a transaction that's no longer stored throws
    /// `missingTransaction` and saves nothing (#264).
    func updateTransaction(_ transaction: Transaction) throws
    func deleteTransaction(id: UUID) throws
    /// Saves new transactions as one batch, with the same rules as `saveTransaction` for each
    /// (`LedgerBook.savingNewTransactions`). An import uses it so 5,000 rows don't save one by one (#30 S35).
    func saveNewTransactions(_ transactions: [Transaction]) throws
    /// Deletes transactions as one batch, the same as `deleteTransaction` for each
    /// (`LedgerBook.deletingTransactions`). Undo Import uses it.
    func deleteTransactions(ids: [UUID]) throws

    func categories() throws -> [TransactionCategory]
    func saveCategory(_ category: TransactionCategory) throws
    func deleteCategory(id: UUID, reassigningTo categoryID: UUID?) throws
    /// See `LedgerBook.mergingCategories(_:into:in:now:)`.
    func mergeCategories(_ sourceID: UUID, into survivingID: UUID) throws
    /// See `LedgerBook.archivingCategory(id:archived:in:now:)`.
    func archiveCategory(id: UUID, archived: Bool) throws
    /// See `LedgerBook.reorderingCategories(_:in:now:)`.
    func reorderCategories(_ orderedIDs: [UUID]) throws
    /// Adds the built-in categories that aren't there yet, with the names `names` gives (D8). Only
    /// `SeedDefaultCategoriesUseCase` calls it, once per store (D291.7).
    func seedDefaultCategories(names: any DefaultCategoryNaming) throws
    /// Whether this store's one-time default-category seeding is still pending (D291.7, D293). It's pending
    /// only from the moment a brand-new store is created until a seed save succeeds or a restore or import
    /// completes, and it survives relaunches in between, so a failed first seed is retried. A store with no
    /// pending marker counts as seeded: existing installs never seed.
    var isDefaultSeedPending: Bool { get }
    /// Records that the seeding is done, for good. Called after a successful seed save, by `replaceLedger` when a
    /// restore completes, and by an import when it completes (#30, #60: none exists yet). It never throws: if the
    /// marker can't be removed it's logged, and the empty-store check still prevents a seed.
    func markDefaultSeedDone()

    func payees() throws -> [Payee]
    func savePayee(_ payee: Payee) throws
    func deletePayee(id: UUID) throws
    func mergePayees(_ sourceID: UUID, into survivingID: UUID) throws
    /// How many live records use this payee, so Undo can tell whether a payee its save created may go
    /// (D191.4): live transactions and live scheduled items. Deleted records don't count, and there is no rule or
    /// split payee yet. A model that gets a payee must join the count.
    func payeeReferenceCount(_ payeeID: UUID) throws -> Int
    /// Which of `ids` live records use: the payees `payeeReferenceCount` counts above zero, found in one pass
    /// (`LedgerSnapshot.payeesInUse`). Undo Import uses it (#250).
    ///
    /// Call it inside `atomically`, where it reads the change's own snapshot. Outside one, a store may load the
    /// whole ledger for it (SwiftData does, attachments included), where `payeeReferenceCount` is a count query.
    func payeesInUse(among ids: Set<UUID>) throws -> Set<UUID>
    /// Deletes payees as one batch, the same as `deletePayee` for each (`LedgerBook.deletingPayees`). A repeated id
    /// counts once. Undo Import uses it (#250).
    func deletePayees(ids: [UUID]) throws

    func tags() throws -> [Tag]
    func saveTag(_ tag: Tag) throws
    func deleteTag(id: UUID) throws

    func splits(for transactionID: UUID?) throws -> [TransactionSplit]
    func replaceSplits(_ splits: [TransactionSplit], for transactionID: UUID) throws

    func attachments(for transactionID: UUID?) throws -> [Attachment]
    func saveAttachment(_ attachment: Attachment) throws
    func deleteAttachment(id: UUID) throws

    /// The current balance: transactions dated up to `today` (D21, `AccountBalance`).
    func balance(of accountID: UUID, today: CalendarDay) throws -> Decimal
    /// Per-currency current net wealth: transactions dated up to `today` (D21, `AccountBalance`).
    func netWorth(today: CalendarDay) throws -> [String: Decimal]

    /// Runs `body` as one all-or-nothing change: every write in it is kept, or, if `body` or the final save
    /// throws, none is. Reads inside `body` see its earlier writes. A nested call joins the outer one; if
    /// it throws, its own writes are undone, and the outer change keeps going only if its caller catches the error.
    func atomically<T>(_ body: () throws -> T) throws -> T

    /// Moves on with every write of the store, kept or failed, so a batch built off the main actor from
    /// `batchBase()` can tell at its commit whether anything wrote since (#285). `nil` for a store without the
    /// batch path, which `batchBase()` and `writeBatch(_:)` then refuse; the use cases save it row by row.
    var revision: UInt64? { get }
    /// The ledger as one value, with the store's clock and `revision`, for a batch built off the main actor
    /// (#285). Inside `atomically` it's the change's own snapshot. Attachments may come without their bytes.
    func batchBase() throws -> LedgerBatchBase
    /// Stores `snapshot`, which `LedgerBook` built from `batchBase()`, as one write with the store's own checks
    /// (#285). Call it inside `atomically`, after comparing `revision` with the base's, so nothing lands between
    /// the check and the write.
    func writeBatch(_ snapshot: LedgerSnapshot) throws
    /// Whether `writeBatchOffMain(_:expectedRevision:)` saves off the main actor, so a progress sheet can draw and
    /// animate during the save instead of going up before it (#285, B).
    var savesBatchesOffMain: Bool { get }
    /// Stores `snapshot` as one write, as `writeBatch(_:)` does, but the save itself may run off the main actor
    /// (#285, B). Call it outside `atomically`, right after building `snapshot` from a base whose revision is
    /// `expectedRevision`. Before its first suspension, on the main actor, it compares that with `revision`: if
    /// the store moved, it writes nothing and returns `false`, so the caller builds the batch again. Otherwise it
    /// writes, all or nothing, and returns `true` once the ledger in memory has the result.
    func writeBatchOffMain(_ snapshot: LedgerSnapshot, expectedRevision: UInt64) async throws -> Bool
}

extension LedgerRepository {
    /// The existence check, then `saveTransaction`, in one change, for a repository without its own update path.
    public func updateTransaction(_ transaction: Transaction) throws {
        try atomically {
            guard try transactions().contains(where: { $0.id == transaction.id }) else {
                throw LedgerValidationError.missingTransaction
            }
            try saveTransaction(transaction)
        }
    }

    /// No batch path: the use cases save row by row, as before #285.
    public var revision: UInt64? { nil }

    public func batchBase() throws -> LedgerBatchBase {
        throw LedgerBatchUnsupported()
    }

    public func writeBatch(_: LedgerSnapshot) throws {
        throw LedgerBatchUnsupported()
    }

    /// Saves on the main actor.
    public var savesBatchesOffMain: Bool { false }

    /// `writeBatch(_:)` in one change on the main actor, after the revision check.
    public func writeBatchOffMain(_ snapshot: LedgerSnapshot, expectedRevision: UInt64) async throws -> Bool {
        guard revision == expectedRevision else {
            return false
        }
        try atomically { try writeBatch(snapshot) }
        return true
    }

    /// One by one, for a repository without a batch path.
    public func saveNewTransactions(_ transactions: [Transaction]) throws {
        try atomically {
            for transaction in transactions {
                try saveTransaction(transaction)
            }
        }
    }

    /// One by one, for a repository without a batch path.
    public func deleteTransactions(ids: [UUID]) throws {
        try atomically {
            for id in ids {
                try deleteTransaction(id: id)
            }
        }
    }

    /// One count per payee, for a repository without a one-pass path.
    public func payeesInUse(among ids: Set<UUID>) throws -> Set<UUID> {
        try ids.filter { try payeeReferenceCount($0) > 0 }
    }

    /// One by one, for a repository without a batch path. A repeated id is dropped, keeping the first in order, so
    /// it counts once as in the batch paths instead of failing as an unknown payee on its second delete.
    public func deletePayees(ids: [UUID]) throws {
        var seen: Set<UUID> = []
        let unique = ids.filter { seen.insert($0).inserted }
        try atomically {
            for id in unique {
                try deletePayee(id: id)
            }
        }
    }
}

/// `batchBase()` or `writeBatch(_:)` on a store without the batch path (`LedgerRepository.revision` is `nil`).
public struct LedgerBatchUnsupported: Error, Equatable, Sendable {
    public init() {}
}
