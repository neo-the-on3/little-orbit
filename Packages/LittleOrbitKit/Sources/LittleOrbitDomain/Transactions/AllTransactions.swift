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
        let live = Self.live(accounts)
        let listed = transactions.compactMap { Self.item($0, in: live) }.sorted(by: Self.isNewer)
        return Self.grouped(listed, today: today)
    }

    /// `list` with the transactions in `changed` taken out and put back as `transactions` now holds them (#341):
    /// the rest keep their places, so only the changed rows are sorted and merged in. The result is exactly what a
    /// full build of `transactions` gives, as long as nothing but the transactions in `changed` differs from what
    /// `list` was built from. A change to an account, a category or a payee needs a full build.
    public func updating(
        _ list: AllTransactionsList,
        changed: Set<UUID>,
        accounts: [Account],
        transactions: [Transaction],
        today: CalendarDay,
    ) -> AllTransactionsList {
        guard !changed.isEmpty else {
            return list
        }
        let live = Self.live(accounts)
        let kept =
            (list.upcoming.map { Item(entry: $0, day: TransactionTiming.day(of: $0.transaction)) }
            + list.days.flatMap { day in day.entries.map { Item(entry: $0, day: day.day) } })
            .filter { !changed.contains($0.entry.id) }
        let updated =
            transactions
            .filter { changed.contains($0.id) }
            .compactMap { Self.item($0, in: live) }
            .sorted(by: Self.isNewer)
        return Self.grouped(Self.merged(kept, updated), today: today)
    }

    /// One listed transaction with the day it's grouped under.
    struct Item {
        var entry: AllTransactionsEntry
        var day: CalendarDay
    }

    static func live(_ accounts: [Account]) -> [UUID: Account] {
        Dictionary(
            accounts.filter { $0.deletedAt == nil }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first },
        )
    }

    /// The row for a stored transaction, or `nil` when it's deleted or no live account lists it.
    static func item(_ transaction: Transaction, in live: [UUID: Account]) -> Item? {
        guard transaction.deletedAt == nil, let account = listingAccount(of: transaction, in: live) else {
            return nil
        }
        let entry = AllTransactionsEntry(
            transaction: transaction,
            account: account,
            effect: LedgerBook.effect(of: transaction, on: account.id),
        )
        return Item(entry: entry, day: TransactionTiming.day(of: transaction))
    }

    /// Two lists, each newest first, as one.
    static func merged(_ lhs: [Item], _ rhs: [Item]) -> [Item] {
        var result: [Item] = []
        result.reserveCapacity(lhs.count + rhs.count)
        var left = lhs.startIndex
        var right = rhs.startIndex
        while left < lhs.endIndex, right < rhs.endIndex {
            if isNewer(rhs[right], than: lhs[left]) {
                result.append(rhs[right])
                right += 1
            } else {
                result.append(lhs[left])
                left += 1
            }
        }
        result.append(contentsOf: lhs[left...])
        result.append(contentsOf: rhs[right...])
        return result
    }

    /// Upcoming, then the days, from rows already newest first.
    static func grouped(_ listed: [Item], today: CalendarDay) -> AllTransactionsList {
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

    private static func isNewer(_ lhs: Item, than rhs: Item) -> Bool {
        if lhs.day != rhs.day {
            return lhs.day > rhs.day
        }
        let lhs = lhs.entry.transaction
        let rhs = rhs.entry.transaction
        if lhs.date != rhs.date {
            return lhs.date > rhs.date
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}

@MainActor
public protocol AllTransactionsUseCase {
    /// The stored ledger the cross-account list is built from (#243, D421). Only the read runs on the main actor;
    /// the list and its rows are built off it (#341).
    func ledger() throws -> TransactionLedger
}

/// Reads the stored ledger only: Upcoming scheduled occurrences come from the account history use case, never
/// from here (D425.3).
@MainActor
public struct DefaultAllTransactionsUseCase: AllTransactionsUseCase {
    private let loadLedger: any LoadTransactionLedgerUseCase

    public init(loadLedger: any LoadTransactionLedgerUseCase) {
        self.loadLedger = loadLedger
    }

    public func ledger() throws -> TransactionLedger {
        try loadLedger.ledger()
    }
}

extension HistoryEntry {
    /// A stored transaction's row with a given effect, for lists that reuse the register's rows (#243).
    public init(transaction: Transaction, effect: Decimal, balanceAfter: Decimal) {
        self.init(transaction: transaction, effect: effect, balanceAfter: balanceAfter, scheduledItemID: nil)
    }
}
