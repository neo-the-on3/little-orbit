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
    func deleteTransaction(id: UUID) throws

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
    /// (D191.4). Today only transactions can: a scheduled occurrence is a transaction, and there is no
    /// scheduled-transaction template, rule or split payee yet. A model that gets a payee must join the count.
    func payeeReferenceCount(_ payeeID: UUID) throws -> Int

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
}
