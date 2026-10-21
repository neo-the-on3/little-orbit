import Foundation
import LittleOrbitDomain

/// A fake `LedgerRepository` for the use-case tests: accounts and transactions in memory, through the same
/// `LedgerBook` rules as the real stores. The rest of the port isn't used by the account use cases and throws.
@MainActor
final class FakeLedgerRepository: LedgerRepository {
    struct Unsupported: Error {}
    struct ReadFailure: Error {}

    private(set) var snapshot = LedgerSnapshot()
    private(set) var savedAccountIDs: [UUID] = []
    var failsReads = false
    private var tick = 0.0

    init(accounts: [Account] = [], transactions: [Transaction] = []) throws {
        for account in accounts {
            try saveAccount(account)
        }
        for transaction in transactions {
            snapshot = try LedgerBook.savingTransaction(transaction, in: snapshot, now: now())
        }
        savedAccountIDs = []
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
        snapshot = try LedgerBook.deletingAccount(id: id, in: snapshot)
    }

    func transactions() throws -> [Transaction] {
        if failsReads {
            throw ReadFailure()
        }
        return snapshot.transactionsVisible()
    }

    func saveTransaction(_ transaction: Transaction) throws { throw Unsupported() }
    func deleteTransaction(id: UUID) throws { throw Unsupported() }
    func recordScheduledOccurrence(_ transaction: Transaction) throws -> Transaction { throw Unsupported() }
    func categories() throws -> [TransactionCategory] { throw Unsupported() }
    func saveCategory(_ category: TransactionCategory) throws { throw Unsupported() }
    func deleteCategory(id: UUID, reassigningTo categoryID: UUID?) throws { throw Unsupported() }
    func seedDefaultCategories() throws { throw Unsupported() }
    func payees() throws -> [Payee] { throw Unsupported() }
    func savePayee(_ payee: Payee) throws { throw Unsupported() }
    func deletePayee(id: UUID) throws { throw Unsupported() }
    func mergePayees(_ sourceID: UUID, into survivingID: UUID) throws { throw Unsupported() }
    func tags() throws -> [Tag] { throw Unsupported() }
    func saveTag(_ tag: Tag) throws { throw Unsupported() }
    func deleteTag(id: UUID) throws { throw Unsupported() }
    func splits(for transactionID: UUID?) throws -> [TransactionSplit] { throw Unsupported() }
    func replaceSplits(_ splits: [TransactionSplit], for transactionID: UUID) throws { throw Unsupported() }
    func attachments(for transactionID: UUID?) throws -> [Attachment] { throw Unsupported() }
    func saveAttachment(_ attachment: Attachment) throws { throw Unsupported() }
    func deleteAttachment(id: UUID) throws { throw Unsupported() }
    func balance(of accountID: UUID, today: CalendarDay) throws -> Decimal {
        try AccountBalance.current(of: accountID, in: snapshot, today: today)
    }
    func netWorth(today: CalendarDay) throws -> [String: Decimal] {
        try AccountBalance.currentNetWorth(in: snapshot, today: today)
    }
}
