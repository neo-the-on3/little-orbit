import Foundation

/// One row of “What do I spend my money on?” (#27): a category's net spending in one currency.
///
/// Each category is its own row, subcategories included, and counts only its own transactions and split lines
/// (D289.1): nothing is rolled up into a parent, so nothing is counted twice.
public struct SpendingReportRow: Identifiable, Equatable, Sendable {
    /// `nil` for the Uncategorised row.
    public var categoryID: UUID?
    /// The category, or `nil` for Uncategorised.
    public var category: TransactionCategory?
    /// The category's parent when it's a subcategory, for its “Parent › Subcategory” name (D289.2).
    public var parent: TransactionCategory?
    /// Expenses minus refunds (D308.8, D19). Below 0 when only a refund is left, such as −300.
    public var amount: Decimal
    /// How many transactions add to this row. A split expense counts once in each row its lines are in.
    public var transactionCount: Int
    /// The row's share of the total in tenths of a percent (169 is 16.9%), with largest-remainder rounding so
    /// the shares add up to exactly 1000. A refund-only row has a negative share. `nil` when the total isn't
    /// above 0, since a share of that means nothing.
    public var shareTenths: Int?

    public var id: UUID? { categoryID }

    public init(
        categoryID: UUID?,
        category: TransactionCategory? = nil,
        parent: TransactionCategory? = nil,
        amount: Decimal,
        transactionCount: Int,
        shareTenths: Int? = nil,
    ) {
        self.categoryID = categoryID
        self.category = category
        self.parent = parent
        self.amount = amount
        self.transactionCount = transactionCount
        self.shareTenths = shareTenths
    }
}

/// “What do I spend my money on?” for one period and one currency (#27 core, D316). Currencies are never added
/// together (D17).
public struct SpendingReport: Equatable, Sendable {
    public var period: ReportPeriod
    /// The whole period, as its title names it. Every day in it counts, future-dated ones included, as budgets
    /// count them (D319.2, S28).
    public var range: ReportDayRange
    public var currencyCode: String
    /// Every currency with spending in the period, the default currency first, then by code. The screen shows a
    /// currency picker only when there's more than one.
    public var currencies: [String]
    /// Sorted by signed amount, largest first, so a negative refund-only row goes below the others.
    public var rows: [SpendingReportRow]
    /// The sum of every row, exactly.
    public var total: Decimal

    public init(
        period: ReportPeriod,
        range: ReportDayRange,
        currencyCode: String,
        currencies: [String],
        rows: [SpendingReportRow],
        total: Decimal,
    ) {
        self.period = period
        self.range = range
        self.currencyCode = currencyCode
        self.currencies = currencies
        self.rows = rows
        self.total = total
    }

    /// No expenses or refunds in the period in this currency: the screen shows its empty state.
    public var isEmpty: Bool { rows.isEmpty }
}

/// One transaction behind a report row: what the drill-down lists (#27). The amounts add up to the row's.
public struct SpendingReportEntry: Identifiable, Equatable, Sendable {
    public var transaction: Transaction
    /// What it adds to the row: an expense or its split lines in this category, or minus a refund.
    public var amount: Decimal
    /// The transaction's own day in its own time zone.
    public var day: CalendarDay
    public var account: Account
    public var payee: Payee?

    public var id: UUID { transaction.id }

    public init(transaction: Transaction, amount: Decimal, day: CalendarDay, account: Account, payee: Payee? = nil) {
        self.transaction = transaction
        self.amount = amount
        self.day = day
        self.account = account
        self.payee = payee
    }
}

/// Builds the spending report from a snapshot, counting the way budgets do (`CategorySpending`, #25):
///
/// - An expense adds to its category; a split expense adds each line to the line's own category instead.
/// - A refund (`isRefund`, linked or not) lowers its category and is never income (D19). A category can go
///   below 0 when only its refund is in the period (Electronics −300).
/// - Other income and transfers never count.
/// - A transaction counts on its own calendar day in its own stored time zone, in whichever period that day
///   falls, future-dated ones too (D319.2, as budgets count them, S28). Deleted transactions and transactions
///   in deleted accounts don't count. A category that's gone counts as Uncategorised.
public enum SpendingReportBuilder {
    public static func report(
        in snapshot: LedgerSnapshot,
        period: ReportPeriod,
        today: CalendarDay,
        currencyCode requested: String?,
        defaultCurrency: String,
    ) -> SpendingReport {
        let range = period.range(today: today)
        let lines = contributions(in: snapshot, range: range)
        let defaultCode = CurrencyCode.normalize(defaultCurrency)
        let currencies = Set(lines.map(\.currency))
            .sorted { lhs, rhs in
                if lhs == defaultCode || rhs == defaultCode {
                    return lhs == defaultCode && rhs != defaultCode
                }
                return lhs < rhs
            }
        let requestedCode = requested.map(CurrencyCode.normalize)
        let currency =
            requestedCode.flatMap { currencies.contains($0) ? $0 : nil } ?? currencies.first ?? requestedCode
            ?? defaultCode

        var amounts: [UUID?: Decimal] = [:]
        var transactions: [UUID?: Set<UUID>] = [:]
        for line in lines where line.currency == currency {
            amounts[line.categoryID, default: 0] += line.amount
            transactions[line.categoryID, default: []].insert(line.transaction.id)
        }
        let categories = Dictionary(
            snapshot.categoriesVisible().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        var rows = amounts.map { categoryID, amount in
            let category = categoryID.flatMap { categories[$0] }
            return SpendingReportRow(
                categoryID: categoryID,
                category: category,
                parent: category?.parentID.flatMap { categories[$0] },
                amount: amount,
                transactionCount: transactions[categoryID]?.count ?? 0,
            )
        }
        rows.sort(by: isOrderedBefore)
        let total = rows.reduce(Decimal(0)) { $0 + $1.amount }
        let shares = ReportShares.tenths(of: rows.map(\.amount), total: total)
        for index in rows.indices {
            rows[index].shareTenths = shares?[index]
        }
        return SpendingReport(
            period: period,
            range: range,
            currencyCode: currency,
            currencies: currencies,
            rows: rows,
            total: total,
        )
    }

    /// The transactions behind one row, newest first. Their amounts add up to the row's amount.
    public static func entries(
        in snapshot: LedgerSnapshot,
        period: ReportPeriod,
        today: CalendarDay,
        currencyCode: String,
        categoryID: UUID?,
    ) -> [SpendingReportEntry] {
        let range = period.range(today: today)
        let currency = CurrencyCode.normalize(currencyCode)
        let payees = Dictionary(snapshot.payeesVisible().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var entries: [UUID: SpendingReportEntry] = [:]
        for line in contributions(in: snapshot, range: range)
        where line.currency == currency && line.categoryID == categoryID {
            if entries[line.transaction.id] != nil {
                entries[line.transaction.id]?.amount += line.amount
            } else {
                entries[line.transaction.id] = SpendingReportEntry(
                    transaction: line.transaction,
                    amount: line.amount,
                    day: line.day,
                    account: line.account,
                    payee: line.transaction.payeeID.flatMap { payees[$0] },
                )
            }
        }
        return entries.values.sorted { lhs, rhs in
            if lhs.day != rhs.day {
                return lhs.day > rhs.day
            }
            if lhs.transaction.date != rhs.transaction.date {
                return lhs.transaction.date > rhs.transaction.date
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // MARK: - Counting

    struct Contribution {
        var transaction: Transaction
        var account: Account
        var currency: String
        var day: CalendarDay
        var categoryID: UUID?
        var amount: Decimal
    }

    /// Every amount that adds to or lowers spending in the range, one per expense, split line or refund.
    static func contributions(in snapshot: LedgerSnapshot, range: ReportDayRange) -> [Contribution] {
        let accounts = Dictionary(
            snapshot.accountsVisible().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        let liveCategories = Set(snapshot.categoriesVisible().map(\.id))
        let linesByTransaction = Dictionary(grouping: snapshot.splitsVisible(), by: \.transactionID)
        func category(_ id: UUID?) -> UUID? {
            id.flatMap { liveCategories.contains($0) ? $0 : nil }
        }
        var result: [Contribution] = []
        for transaction in snapshot.transactions where transaction.deletedAt == nil {
            guard let account = transaction.accountID.flatMap({ accounts[$0] }) else {
                continue
            }
            let day = TransactionCalendar.ownDay(of: transaction.date, timeZoneID: transaction.timeZoneID)
            guard range.contains(day) else {
                continue
            }
            func add(_ amount: Decimal, _ categoryID: UUID?) {
                result.append(
                    Contribution(
                        transaction: transaction,
                        account: account,
                        currency: CurrencyCode.normalize(account.currencyCode),
                        day: day,
                        categoryID: category(categoryID),
                        amount: amount,
                    )
                )
            }
            switch transaction.type {
            case .expense:
                let lines = linesByTransaction[transaction.id] ?? []
                if lines.isEmpty {
                    add(transaction.amount, transaction.categoryID)
                } else {
                    for line in lines {
                        add(line.amount, line.categoryID)
                    }
                }
            case .income where transaction.isRefund:
                add(-transaction.amount, transaction.categoryID)
            case .income, .transfer:
                continue
            }
        }
        return result
    }

    /// Largest signed amount first; ties by name, Uncategorised last among equals, then by ID, so the order
    /// never changes between loads.
    static func isOrderedBefore(_ lhs: SpendingReportRow, _ rhs: SpendingReportRow) -> Bool {
        if lhs.amount != rhs.amount {
            return lhs.amount > rhs.amount
        }
        switch (lhs.category, rhs.category) {
        case (let left?, let right?):
            let leftName = sortName(left, parent: lhs.parent)
            let rightName = sortName(right, parent: rhs.parent)
            if leftName != rightName {
                return leftName < rightName
            }
            return left.id.uuidString < right.id.uuidString
        case (.some, .none):
            return true
        case (.none, _):
            return false
        }
    }

    private static func sortName(_ category: TransactionCategory, parent: TransactionCategory?) -> String {
        [parent?.name, category.name].compactMap(\.self).joined(separator: "\u{1F}").lowercased()
    }
}

/// Shares of a total in tenths of a percent that add up to exactly 1000 (UI Designer's #27 decision 2:
/// largest-remainder rounding, one decimal).
public enum ReportShares {
    /// `nil` when `total` isn't above 0.
    public static func tenths(of amounts: [Decimal], total: Decimal) -> [Int]? {
        guard total > 0, !amounts.isEmpty else {
            return nil
        }
        let exact = amounts.map { $0 * 1000 / total }
        let floors = exact.map(floor)
        let remainders = zip(exact, floors).map { $0 - $1 }
        var result = floors.map { NSDecimalNumber(decimal: $0).intValue }
        let missing = 1000 - result.reduce(0, +)
        let order = remainders.indices.sorted { lhs, rhs in
            remainders[lhs] != remainders[rhs] ? remainders[lhs] > remainders[rhs] : lhs < rhs
        }
        for index in order.prefix(max(0, missing)) {
            result[index] += 1
        }
        return result
    }

    /// The largest whole number not above `value`, for negative shares too.
    static func floor(_ value: Decimal) -> Decimal {
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        return rounded > value ? rounded - 1 : rounded
    }
}
