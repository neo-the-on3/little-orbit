import Foundation

/// A category in one currency. Amounts in different currencies are never added together.
public struct CategoryCurrency: Hashable, Sendable {
    /// `nil` for uncategorised.
    public var categoryID: UUID?
    public var currencyCode: String

    public init(categoryID: UUID?, currencyCode: String) {
        self.categoryID = categoryID
        self.currencyCode = currencyCode
    }
}

/// Per-category totals for budgets (#25) and category reports (#27), so both count refunds the same way.
///
/// - An expense adds to its category; a split expense adds each line to the line's category instead.
/// - A refund (`isRefund`, linked or not) lowers its category's spending and is never income (D19, #55). Net
///   spending can go below 0 (D33.2).
/// - Other income is income in its category. Transfers count in neither.
/// - A transaction counts on its own calendar day in its own stored time zone, never the device's (D33.3,
///   D35.4), so the range can be any period: a month, a week or a custom one. Its account's currency keys
///   the total. Deleted transactions and accounts don't count.
public enum CategorySpending {
    /// Net spending per category and currency for transactions dated from `start` through `end`.
    public static func spending(
        in snapshot: LedgerSnapshot,
        from start: CalendarDay,
        through end: CalendarDay,
    ) -> [CategoryCurrency: Decimal] {
        var totals: [CategoryCurrency: Decimal] = [:]
        func add(_ amount: Decimal, to categoryID: UUID?, in currency: String) {
            totals[CategoryCurrency(categoryID: categoryID, currencyCode: currency), default: 0] += amount
        }
        // Grouped once, so a read doesn't scan every split for each expense.
        let linesByTransaction = Dictionary(grouping: snapshot.splitsVisible(), by: \.transactionID)
        for (transaction, currency) in counted(in: snapshot, from: start, through: end) {
            switch transaction.type {
            case .expense:
                let lines = linesByTransaction[transaction.id] ?? []
                if lines.isEmpty {
                    add(transaction.amount, to: transaction.categoryID, in: currency)
                } else {
                    for line in lines {
                        add(line.amount, to: line.categoryID, in: currency)
                    }
                }
            case .income where transaction.isRefund:
                add(-transaction.amount, to: transaction.categoryID, in: currency)
            case .income, .transfer:
                continue
            }
        }
        return totals
    }

    /// Income per category and currency for the same days, refunds left out (D19).
    public static func income(
        in snapshot: LedgerSnapshot,
        from start: CalendarDay,
        through end: CalendarDay,
    ) -> [CategoryCurrency: Decimal] {
        var totals: [CategoryCurrency: Decimal] = [:]
        for (transaction, currency) in counted(in: snapshot, from: start, through: end)
        where transaction.type == .income && !transaction.isRefund {
            totals[CategoryCurrency(categoryID: transaction.categoryID, currencyCode: currency), default: 0] +=
                transaction.amount
        }
        return totals
    }

    /// The net spending of these categories together, in `currencyCode`.
    public static func spent(
        on categories: Set<UUID>,
        currencyCode: String,
        in snapshot: LedgerSnapshot,
        from start: CalendarDay,
        through end: CalendarDay,
    ) -> Decimal {
        spending(in: snapshot, from: start, through: end)
            .filter { key, _ in
                key.currencyCode == currencyCode && key.categoryID.map(categories.contains) == true
            }
            .values
            .reduce(Decimal(0), +)
    }

    /// The live transactions dated in the range, with their account's currency.
    private static func counted(
        in snapshot: LedgerSnapshot,
        from start: CalendarDay,
        through end: CalendarDay,
    ) -> [(Transaction, String)] {
        var currencies: [UUID: String] = [:]
        for account in snapshot.accounts where account.deletedAt == nil {
            currencies[account.id] = account.currencyCode
        }
        return snapshot.transactions.compactMap { transaction in
            guard transaction.deletedAt == nil,
                let currency = transaction.accountID.flatMap({ currencies[$0] }),
                let day = TransactionCalendar.calendarDay(of: transaction),
                start <= day, day <= end
            else {
                return nil
            }
            return (transaction, currency)
        }
    }
}

/// One budget period's figures from its net spending (D33.2, D35.3). Negative net spending, from refunds, is
/// shown as 0 spent plus that much credit, never hidden, and it raises what's left.
public struct BudgetFigures: Equatable, Sendable {
    public var budget: Decimal
    public var netSpending: Decimal
    /// What's left from the previous period when rollover is on (#25); 0 when it's off.
    public var carriedOver: Decimal

    public init(budget: Decimal, netSpending: Decimal, carriedOver: Decimal = 0) {
        self.budget = budget
        self.netSpending = netSpending
        self.carriedOver = carriedOver
    }

    /// Net spending, never below 0.
    public var spent: Decimal { max(0, netSpending) }
    /// The part of net spending below 0, shown next to spent.
    public var credit: Decimal { max(0, -netSpending) }
    /// The budget for the period, with what rolled over.
    public var available: Decimal { budget + carriedOver }
    /// What's left: available minus net spending, so a credit makes it more than the budget.
    public var remaining: Decimal { available - netSpending }
}
