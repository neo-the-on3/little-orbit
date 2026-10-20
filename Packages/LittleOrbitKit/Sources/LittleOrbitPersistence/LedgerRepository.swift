import Foundation
import LittleOrbitDomain

/// Persistence boundary used by the apps. The in-memory store works everywhere. SwiftData is the on-device store.
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
    func seedDefaultCategories() throws

    func payees() throws -> [Payee]
    func savePayee(_ payee: Payee) throws
    func deletePayee(id: UUID) throws
    func mergePayees(_ sourceID: UUID, into survivingID: UUID) throws

    func tags() throws -> [Tag]
    func saveTag(_ tag: Tag) throws
    func deleteTag(id: UUID) throws

    func splits(for transactionID: UUID?) throws -> [TransactionSplit]
    func replaceSplits(_ splits: [TransactionSplit], for transactionID: UUID) throws

    func attachments(for transactionID: UUID?) throws -> [Attachment]
    func saveAttachment(_ attachment: Attachment) throws
    func deleteAttachment(id: UUID) throws

    func balance(of accountID: UUID) throws -> Decimal
    func netWorth() throws -> [String: Decimal]
}
