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
    func recordScheduledOccurrence(_ transaction: Transaction) throws -> Transaction

    func categories() throws -> [TransactionCategory]
    func saveCategory(_ category: TransactionCategory) throws
    func deleteCategory(id: UUID, reassigningTo categoryID: UUID?) throws
    /// Adds the built-in categories that aren't there yet, with the names `names` gives (D8).
    func seedDefaultCategories(names: any DefaultCategoryNaming) throws

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
