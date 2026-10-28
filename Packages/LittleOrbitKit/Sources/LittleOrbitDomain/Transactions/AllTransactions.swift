import Foundation

/// One row of the cross-account list (#243, D421): a stored transaction, the one account it's listed under, and
/// its signed effect on that account. A transfer is listed once, under its source account (D25, D421.5).
public struct AllTransactionsEntry: Equatable, Sendable, Identifiable {
    public var transaction: Transaction
    public var account: Account
    public var effect: Decimal

    public var id: UUID { transaction.id }

    public init(transaction: Transaction, account: Account, effect: Decimal) {
        self.transaction = transaction
        self.account = account
        self.effect = effect
    }
}

/// A calendar day of the cross-account list, in each transaction's own time zone, as account history groups it.
public struct AllTransactionsDay: Equatable, Sendable, Identifiable {
    public var day: CalendarDay
    public var entries: [AllTransactionsEntry]

    public var id: CalendarDay { day }
}

/// Every stored transaction in every live account, hidden ones included (D421.10, D22), newest first.
public struct AllTransactionsList: Equatable, Sendable {
    /// Stored transactions dated after today, newest first, as account history's Upcoming (D426.4). A scheduled
    /// occurrence that isn't recorded yet is never listed (D425.3).
    public var upcoming: [AllTransactionsEntry]
    /// Past and today, grouped by day, newest first.
    public var days: [AllTransactionsDay]

    public var isEmpty: Bool { upcoming.isEmpty && days.isEmpty }

    /// Every entry in display order: Upcoming, then the days.
    public var entries: [AllTransactionsEntry] { upcoming + days.flatMap(\.entries) }
}

/// Builds the cross-account list (#243). The order is account history's, reversed: entry day, then time, then
/// creation, then id, newest first, so rows that tie keep the order they have in their account's register.
public struct BuildAllTransactions: Sendable {
    public init() {}

    public func callAsFunction(
        accounts: [Account],
        transactions: [Transaction],
        today: CalendarDay,
    ) -> AllTransactionsList {
        let live = Dictionary(
            accounts.filter { $0.deletedAt == nil }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        let listed =
            transactions
            .filter { $0.deletedAt == nil }
            .compactMap { transaction -> (entry: AllTransactionsEntry, day: CalendarDay)? in
                guard let account = Self.listingAccount(of: transaction, in: live) else {
                    return nil
                }
                let entry = AllTransactionsEntry(
                    transaction: transaction,
                    account: account,
                    effect: LedgerBook.effect(of: transaction, on: account.id),
                )
                return (entry, TransactionTiming.day(of: transaction))
            }
            .sorted { lhs, rhs in Self.isNewer(lhs.entry.transaction, lhs.day, than: rhs.entry.transaction, rhs.day) }
        var upcoming: [AllTransactionsEntry] = []
        var days: [AllTransactionsDay] = []
        for item in listed {
            if item.day > today {
                upcoming.append(item.entry)
            } else if let last = days.last, last.day == item.day {
                days[days.count - 1].entries.append(item.entry)
            } else {
                days.append(AllTransactionsDay(day: item.day, entries: [item.entry]))
            }
        }
        return AllTransactionsList(upcoming: upcoming, days: days)
    }

    /// The account a transaction is listed under: its own account, which for a transfer is the source (D25). A
    /// transfer whose source is gone is listed under its destination, so it never vanishes while one leg remains.
    static func listingAccount(of transaction: Transaction, in live: [UUID: Account]) -> Account? {
        if let id = transaction.accountID, let account = live[id] {
            return account
        }
        if transaction.type == .transfer, let id = transaction.transferAccountID {
            return live[id]
        }
        return nil
    }

    private static func isNewer(
        _ lhs: Transaction,
        _ lhsDay: CalendarDay,
        than rhs: Transaction,
        _ rhsDay: CalendarDay,
    )
        -> Bool
    {
        if lhsDay != rhsDay {
            return lhsDay > rhsDay
        }
        if lhs.date != rhs.date {
            return lhs.date > rhs.date
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}

/// The cross-account list with the records its rows name: accounts, categories and payees.
public struct AllTransactionsPage: Equatable, Sendable {
    public var list: AllTransactionsList
    public var ledger: TransactionLedger

    public init(list: AllTransactionsList, ledger: TransactionLedger) {
        self.list = list
        self.ledger = ledger
    }
}

@MainActor
public protocol AllTransactionsUseCase {
    /// Every stored transaction across the live accounts as of `today` (#243, D421).
    func allTransactions(today: CalendarDay) throws -> AllTransactionsPage
}

/// Reads the stored ledger only: Upcoming scheduled occurrences come from the account history use case, never
/// from here (D425.3).
@MainActor
public struct DefaultAllTransactionsUseCase: AllTransactionsUseCase {
    private let loadLedger: any LoadTransactionLedgerUseCase
    private let build = BuildAllTransactions()

    public init(loadLedger: any LoadTransactionLedgerUseCase) {
        self.loadLedger = loadLedger
    }

    public func allTransactions(today: CalendarDay) throws -> AllTransactionsPage {
        let ledger = try loadLedger.ledger()
        let list = build(accounts: ledger.accounts, transactions: ledger.transactions, today: today)
        return AllTransactionsPage(list: list, ledger: ledger)
    }
}

extension HistoryEntry {
    /// A stored transaction's row with a given effect, for lists that reuse the register's rows (#243).
    public init(transaction: Transaction, effect: Decimal, balanceAfter: Decimal) {
        self.init(transaction: transaction, effect: effect, balanceAfter: balanceAfter, scheduledItemID: nil)
    }
}
