import Foundation

/// One transaction as a budget counts it in a period (#25 part 4, D117.10, D237): an expense, one line of a split
/// expense, or a refund. Lines of one split in the same category are one line.
public struct BudgetActivityLine: Identifiable, Equatable, Sendable {
    /// The transaction's ID with the line's category, since a split can have lines in two picked categories.
    public var id: String
    public var transaction: Transaction
    /// The transaction's own calendar day (#11).
    public var day: CalendarDay
    /// The expense's category, or the split line's.
    public var categoryID: UUID?
    /// What counts toward spent: positive for an expense or split line, negative for a refund.
    public var amount: Decimal
    /// Only this line of a split expense is in the budget (S73).
    public var isSplitLine: Bool
    /// Whether it's a refund and whether its original is still there (D19, S74).
    public var refund: RefundStatus

    public init(
        transaction: Transaction,
        day: CalendarDay,
        categoryID: UUID?,
        amount: Decimal,
        isSplitLine: Bool,
    ) {
        id = "\(transaction.id.uuidString)/\(categoryID?.uuidString ?? "-")"
        self.transaction = transaction
        self.day = day
        self.categoryID = categoryID
        self.amount = amount
        self.isSplitLine = isSplitLine
        refund = RefundStatus(of: transaction)
    }
}

/// The period's expenses in a budget's categories from one account in another currency (D17, D307.3). They
/// aren't counted, and the detail names the account and how many there are.
public struct BudgetExcludedAccount: Equatable, Sendable {
    public var accountID: UUID?
    public var currencyCode: String
    /// The transactions left out, each counted once however many of its lines are in the budget's categories.
    public var transactionCount: Int

    public init(accountID: UUID?, currencyCode: String, transactionCount: Int) {
        self.accountID = accountID
        self.currencyCode = currencyCode
        self.transactionCount = transactionCount
    }
}

/// A budget's detail for one period (#25 part 4): its figures, the transactions that count, newest first, and
/// the records the screen names them by. Facts only; the screen words them.
public struct BudgetDetail: Equatable, Sendable {
    public var budget: Budget
    /// The current period, or the first before the start date, with the days to the next period.
    public var summary: BudgetSummary
    /// The period on show.
    public var selected: BudgetPeriodFigures
    /// The index of the current period (or 0 before the start date); later periods aren't shown.
    public var currentIndex: Int
    /// The selected period's transactions in the budget's categories and currency, newest first.
    public var lines: [BudgetActivityLine]
    /// The selected period's transactions in the budget's categories in another currency, by account, in the
    /// order the accounts were first seen; empty when every one is in the budget's currency.
    public var excludedAccounts: [BudgetExcludedAccount]
    /// The live categories, for the budget's category names and each line's.
    public var categories: [TransactionCategory]
    /// The live accounts, for each line's account name.
    public var accounts: [Account]
    /// The live payees, for each line's title.
    public var payees: [Payee]

    public init(
        budget: Budget,
        summary: BudgetSummary,
        selected: BudgetPeriodFigures,
        currentIndex: Int,
        lines: [BudgetActivityLine],
        excludedAccounts: [BudgetExcludedAccount] = [],
        categories: [TransactionCategory],
        accounts: [Account],
        payees: [Payee],
    ) {
        self.budget = budget
        self.summary = summary
        self.selected = selected
        self.currentIndex = currentIndex
        self.lines = lines
        self.excludedAccounts = excludedAccounts
        self.categories = categories
        self.accounts = accounts
        self.payees = payees
    }

    /// No category the budget picked is left (D307.5).
    public var hasNoCategories: Bool {
        summary.hasNoCategories
    }

    /// Whether the period on show is the current one (or the first, before the start date).
    public var isCurrentPeriod: Bool {
        selected.period.index == currentIndex
    }

    /// Works out the detail from `snapshot`, with `index` clamped to the first through the current period.
    public init(of budget: Budget, period index: Int?, today: CalendarDay, in snapshot: LedgerSnapshot) {
        let summary = BudgetProgress.summary(of: budget, today: today, in: snapshot)
        let current = budget.schedule.currentOrFirstPeriod(today: today).index
        let shown = min(max(index ?? current, 0), current)
        var selected =
            shown == current ? summary.current : BudgetProgress.figures(of: budget, period: shown, in: snapshot)
        if shown == current, summary.current.state == .notStarted {
            selected.state = .notStarted
        }
        let activity = Self.activity(of: budget, in: selected.period, snapshot: snapshot)
        self.init(
            budget: budget,
            summary: summary,
            selected: selected,
            currentIndex: current,
            lines: activity.lines,
            excludedAccounts: activity.excluded,
            categories: snapshot.categoriesVisible(),
            accounts: snapshot.accountsVisible(),
            payees: snapshot.payeesVisible(),
        )
    }

    /// In one pass over the period's entries in the budget's categories: the counted amounts in the budget's
    /// currency, one line per transaction and category, newest first (by day, then by when they were added); and
    /// the transactions in other currencies, by account.
    static func activity(
        of budget: Budget,
        in period: BudgetPeriod,
        snapshot: LedgerSnapshot,
    ) -> (lines: [BudgetActivityLine], excluded: [BudgetExcludedAccount]) {
        let covered = BudgetCategories.covered(by: budget, in: snapshot)
        let transactions = Dictionary(
            snapshot.transactions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        var lines: [String: BudgetActivityLine] = [:]
        var order: [String] = []
        var excluded: [BudgetExcludedAccount] = []
        var excludedTransactions: Set<UUID> = []
        for entry in CategorySpending.entries(in: snapshot, from: period.start, through: period.end) {
            guard let categoryID = entry.categoryID, covered.contains(categoryID),
                let transaction = entry.transactionID.flatMap({ transactions[$0] })
            else {
                continue
            }
            guard entry.currencyCode == budget.currencyCode else {
                guard excludedTransactions.insert(transaction.id).inserted else {
                    continue
                }
                if let index = excluded.firstIndex(where: {
                    $0.accountID == transaction.accountID && $0.currencyCode == entry.currencyCode
                }) {
                    excluded[index].transactionCount += 1
                } else {
                    excluded.append(
                        BudgetExcludedAccount(
                            accountID: transaction.accountID,
                            currencyCode: entry.currencyCode,
                            transactionCount: 1,
                        )
                    )
                }
                continue
            }
            let line = BudgetActivityLine(
                transaction: transaction,
                day: entry.day,
                categoryID: categoryID,
                amount: entry.amount,
                isSplitLine: entry.isSplitLine,
            )
            if lines[line.id] == nil {
                lines[line.id] = line
                order.append(line.id)
            } else {
                lines[line.id]?.amount += entry.amount
            }
        }
        let sorted = order.compactMap { lines[$0] }
            .sorted { lhs, rhs in
                if lhs.day != rhs.day {
                    return lhs.day > rhs.day
                }
                if lhs.transaction.date != rhs.transaction.date {
                    return lhs.transaction.date > rhs.transaction.date
                }
                if lhs.transaction.createdAt != rhs.transaction.createdAt {
                    return lhs.transaction.createdAt > rhs.transaction.createdAt
                }
                return lhs.id < rhs.id
            }
        return (sorted, excluded)
    }
}
