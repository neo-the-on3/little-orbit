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
///
/// A screen that searches the same read again on each keystroke keeps a `TransactionSearchIndex` and runs that
/// instead (#340); this one-off search makes the index and runs it once.
public enum TransactionSearch {
    public static func run(
        _ query: TransactionSearchQuery,
        filter: TransactionSearchFilter = TransactionSearchFilter(),
        in ledger: TransactionSearchLedger,
        today: CalendarDay,
        defaultCurrency: String,
    ) -> TransactionSearchResult {
        TransactionSearchIndex(ledger).run(query, filter: filter, today: today, defaultCurrency: defaultCurrency)
    }
}
