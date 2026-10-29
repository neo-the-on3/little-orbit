import Foundation

/// The records a search reads: live accounts (hidden ones included, D22), transactions and the names they refer to.
public struct TransactionSearchLedger: Equatable, Sendable {
    public var accounts: [Account]
    public var transactions: [Transaction]
    public var categories: [TransactionCategory]
    public var payees: [Payee]
    public var tags: [Tag]

    public init(
        accounts: [Account] = [],
        transactions: [Transaction] = [],
        categories: [TransactionCategory] = [],
        payees: [Payee] = [],
        tags: [Tag] = [],
    ) {
        self.accounts = accounts
        self.transactions = transactions
        self.categories = categories
        self.payees = payees
        self.tags = tags
    }
}

/// Filters the screen applies on top of the typed query: the scope bar's type, and an account (D25).
public struct TransactionSearchFilter: Equatable, Sendable {
    /// Expenses, Income or Transfers; `nil` is All. A refund is an expense here (D46).
    public var type: TransactionType?
    /// Only this account's transactions, each transfer from this account's side (D25).
    public var accountID: UUID?

    public init(type: TransactionType? = nil, accountID: UUID? = nil) {
        self.type = type
        self.accountID = accountID
    }
}

/// One matching transaction as it's listed: under one account, in that account's currency, with its signed effect.
public struct TransactionSearchMatch: Equatable, Sendable, Identifiable {
    public var transaction: Transaction
    /// The filtered account, else the transaction's own account, which for a transfer is the sending side (D25).
    public var accountID: UUID
    public var currencyCode: String
    /// The signed effect on `accountID`: −1,000 for a transfer sent, +12 for the same one received.
    public var effect: Decimal
    /// Dated after today: listed, but never in a total (D47, D120.2).
    public var isUpcoming: Bool

    public var id: UUID { transaction.id }
}

/// One currency's figures. Amounts in different currencies are never added together (D17).
public struct TransactionSearchTotals: Equatable, Sendable {
    public var currencyCode: String
    public var income: Decimal = 0
    /// Expenses less refunds (D31). It's negative when only refunds remain.
    public var expenses: Decimal = 0
    /// What transfers moved, at the listed side's amount (D25). Never part of income, expenses or net (D56).
    public var moved: Decimal = 0
    /// Whether any expense, income or refund counted. Without one, the currency shows the amount moved (D56, D111).
    public var hasIncomeOrExpense = false

    public init(currencyCode: String) {
        self.currencyCode = currencyCode
    }

    /// Income minus expenses, refunds counted as negative spending.
    public var net: Decimal { income - expenses }

    mutating func add(_ match: TransactionSearchMatch) {
        let transaction = match.transaction
        switch transaction.type {
        case .expense:
            expenses += transaction.amount
            hasIncomeOrExpense = true
        case .income where transaction.isRefund:
            expenses -= transaction.amount
            hasIncomeOrExpense = true
        case .income:
            income += transaction.amount
            hasIncomeOrExpense = true
        case .transfer:
            moved += match.effect.magnitude
        }
    }
}

/// A calendar day of results, newest rows first, with its own figures per currency (D56, D107).
public struct TransactionSearchDay: Equatable, Sendable, Identifiable {
    public var day: CalendarDay
    /// After today: the header is muted and the day counts in no total (D107, D47).
    public var isUpcoming: Bool
    public var matches: [TransactionSearchMatch]
    /// Default currency first, then by code.
    public var totals: [TransactionSearchTotals]

    public var id: CalendarDay { day }
}

public struct TransactionSearchResult: Equatable, Sendable {
    /// Newest first, so Upcoming days come before today.
    public var days: [TransactionSearchDay]
    /// The counted figures: everything dated up to today. Default currency first, then by code.
    public var totals: [TransactionSearchTotals]
    /// Every match, Upcoming ones included (D47).
    public var count: Int
    public var upcomingCount: Int
    public var issues: [TransactionSearchIssue]

    public init(
        days: [TransactionSearchDay] = [],
        totals: [TransactionSearchTotals] = [],
        count: Int = 0,
        upcomingCount: Int = 0,
        issues: [TransactionSearchIssue] = [],
    ) {
        self.days = days
        self.totals = totals
        self.count = count
        self.upcomingCount = upcomingCount
        self.issues = issues
    }
}

/// Finds transactions for #28 and works out the result count, totals and day figures.
///
/// Text matches ignore case and diacritics and follow the user's locale (`localizedStandardContains`), so “cafe”
/// finds “Café Noir”. Plain words match the description, category, payee, tags or notes. Dates are each
/// transaction's own calendar day in the zone it was entered in, never the device's (#11, D21).
public enum TransactionSearch {
    public static func run(
        _ query: TransactionSearchQuery,
        filter: TransactionSearchFilter = TransactionSearchFilter(),
        in ledger: TransactionSearchLedger,
        today: CalendarDay,
        defaultCurrency: String,
    ) -> TransactionSearchResult {
        let names = Names(ledger)
        let accounts = Dictionary(
            ledger.accounts.filter { $0.deletedAt == nil }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        var found: [(day: CalendarDay, match: TransactionSearchMatch)] = []
        for transaction in ledger.transactions where transaction.deletedAt == nil {
            guard let listedID = listedAccount(of: transaction, filter: filter),
                let account = accounts[listedID],
                Self.type(transaction, matches: filter.type)
            else {
                continue
            }
            let day = TransactionTiming.day(of: transaction)
            guard matches(transaction, day: day, query: query, names: names) else {
                continue
            }
            let match = TransactionSearchMatch(
                transaction: transaction,
                accountID: listedID,
                currencyCode: account.currencyCode,
                effect: LedgerBook.effect(of: transaction, on: listedID),
                isUpcoming: day > today,
            )
            found.append((day, match))
        }
        let order = CurrencyOrder(defaultCurrency: defaultCurrency)
        let days = Dictionary(grouping: found, by: \.day)
            .map { day, items in
                let rows = items.map(\.match).sorted(by: newestFirst)
                return TransactionSearchDay(
                    day: day,
                    isUpcoming: day > today,
                    matches: rows,
                    totals: order.totals(of: rows),
                )
            }
            .sorted { $0.day > $1.day }
        let counted = found.map(\.match).filter { !$0.isUpcoming }
        return TransactionSearchResult(
            days: days,
            totals: order.totals(of: counted),
            count: found.count,
            upcomingCount: found.count - counted.count,
            issues: query.issues,
        )
    }

    // MARK: - Matching

    /// Category, payee and tag names by id, read once per search.
    private struct Names {
        var categories: [UUID: String] = [:]
        var payees: [UUID: String] = [:]
        var tags: [UUID: String] = [:]

        init(_ ledger: TransactionSearchLedger) {
            for category in ledger.categories where category.deletedAt == nil {
                categories[category.id] = category.name
            }
            for payee in ledger.payees where payee.deletedAt == nil {
                payees[payee.id] = payee.name
            }
            for tag in ledger.tags where tag.deletedAt == nil {
                tags[tag.id] = tag.name
            }
        }
    }

    private static func listedAccount(of transaction: Transaction, filter: TransactionSearchFilter) -> UUID? {
        guard let scoped = filter.accountID else {
            return transaction.accountID
        }
        let touches = transaction.accountID == scoped || transaction.transferAccountID == scoped
        return touches ? scoped : nil
    }

    /// The kind a transaction counts as: a refund is an expense, never income (D46).
    private static func kind(of transaction: Transaction) -> TransactionType {
        transaction.type == .income && transaction.isRefund ? .expense : transaction.type
    }

    private static func type(_ transaction: Transaction, matches type: TransactionType?) -> Bool {
        type.map { kind(of: transaction) == $0 } ?? true
    }

    private static func matches(
        _ transaction: Transaction,
        day: CalendarDay,
        query: TransactionSearchQuery,
        names: Names,
    ) -> Bool {
        if let after = query.after, day < after {
            return false
        }
        if let before = query.before, day > before {
            return false
        }
        guard query.years.allSatisfy({ $0 == day.year }),
            query.types.allSatisfy({ $0 == kind(of: transaction) })
        else {
            return false
        }
        let category = transaction.categoryID.flatMap { names.categories[$0] }
        let payee = transaction.payeeID.flatMap { names.payees[$0] }
        let tags = transaction.tagIDs.compactMap { names.tags[$0] }
        guard query.categories.allSatisfy({ contains(category, $0) }),
            query.payees.allSatisfy({ contains(payee, $0) }),
            query.notes.allSatisfy({ contains(transaction.note, $0) }),
            query.tags.allSatisfy({ value in tags.contains { contains($0, value) } })
        else {
            return false
        }
        let fields = [transaction.details, category, payee, transaction.note] + tags.map(Optional.some)
        return query.terms.allSatisfy { term in fields.contains { contains($0, term) } }
    }

    /// Locale-aware, case- and diacritic-insensitive (`localizedStandardContains`).
    static func contains(_ field: String?, _ text: String) -> Bool {
        field?.localizedStandardContains(text) ?? false
    }

    private static func newestFirst(_ lhs: TransactionSearchMatch, _ rhs: TransactionSearchMatch) -> Bool {
        if lhs.transaction.date != rhs.transaction.date {
            return lhs.transaction.date > rhs.transaction.date
        }
        if lhs.transaction.createdAt != rhs.transaction.createdAt {
            return lhs.transaction.createdAt > rhs.transaction.createdAt
        }
        return lhs.transaction.id.uuidString < rhs.transaction.id.uuidString
    }

    /// Default currency first, then by code (D107), as net wealth orders them.
    private struct CurrencyOrder {
        let defaultCurrency: String

        init(defaultCurrency: String) {
            self.defaultCurrency = CurrencyCode.normalize(defaultCurrency)
        }

        func totals(of matches: [TransactionSearchMatch]) -> [TransactionSearchTotals] {
            var byCurrency: [String: TransactionSearchTotals] = [:]
            for match in matches {
                byCurrency[match.currencyCode, default: TransactionSearchTotals(currencyCode: match.currencyCode)]
                    .add(match)
            }
            return byCurrency.values.sorted { lhs, rhs in
                if (lhs.currencyCode == defaultCurrency) != (rhs.currencyCode == defaultCurrency) {
                    return lhs.currencyCode == defaultCurrency
                }
                return lhs.currencyCode < rhs.currencyCode
            }
        }
    }
}
