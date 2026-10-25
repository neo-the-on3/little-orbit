import Foundation

/// The categories a budget counts (D217).
public enum BudgetCategories {
    /// The picked categories and every subcategory now under a picked parent, worked out from the category tree
    /// as it is now, for every period (D217.1, D217.6). Archived categories still count (D217.7); deleted ones
    /// don't. One set, so nothing is counted twice even when a parent and its subcategory are both picked
    /// (D217.3).
    public static func covered(by budget: Budget, in snapshot: LedgerSnapshot) -> Set<UUID> {
        let live = snapshot.categoriesVisible()
        let liveIDs = Set(live.map(\.id))
        var covered: Set<UUID> = []
        for id in budget.categoryIDs where liveIDs.contains(id) {
            covered.formUnion(LedgerBook.subtreeIDs(of: id, in: live))
        }
        return covered
    }
}

/// Where a budget stands in a period (#25).
public enum BudgetState: Hashable, Sendable {
    /// Today is before the budget's start day.
    case notStarted
    case onTrack
    /// Spent is 90% or more of what's available, and not over it.
    case nearLimit
    /// Spent is more than what's available. Exactly at the limit isn't overspent (S21).
    case overspent
}

/// A budget's figures for one period.
public struct BudgetPeriodFigures: Equatable, Sendable {
    public var period: BudgetPeriod
    /// The limit that applies to this period. Earlier periods keep their own (#25).
    public var limit: Decimal
    /// Net spending, what was carried in, and what's left. `figures.budget` is `limit`.
    public var figures: BudgetFigures
    /// What this period passes to the next one: what's left when carrying over unspent, or the overspending
    /// when carrying over overspending; otherwise 0.
    public var carriedForward: Decimal
    public var state: BudgetState
    /// The other currencies with expenses in the budget's categories this period. They aren't counted (D17), and
    /// the budget shows a hint.
    public var excludedCurrencies: [String]
    /// No live account is in the budget's currency, so nothing can count yet; the budget shows the same hint
    /// (D307.3).
    public var hasNoAccountInCurrency: Bool

    public init(
        period: BudgetPeriod,
        limit: Decimal,
        figures: BudgetFigures,
        carriedForward: Decimal,
        state: BudgetState,
        excludedCurrencies: [String] = [],
        hasNoAccountInCurrency: Bool = false,
    ) {
        self.period = period
        self.limit = limit
        self.figures = figures
        self.carriedForward = carriedForward
        self.state = state
        self.excludedCurrencies = excludedCurrencies
        self.hasNoAccountInCurrency = hasNoAccountInCurrency
    }

    /// Whether the budget shows the other-currency hint: other-currency expenses this period, or no account in its
    /// currency (D307.3).
    public var showsCurrencyHint: Bool {
        !excludedCurrencies.isEmpty || hasNoAccountInCurrency
    }
}

/// One row of the budget list: the budget and its current period.
public struct BudgetSummary: Identifiable, Equatable, Sendable {
    public var budget: Budget
    /// The period containing today, or the first period before the budget starts.
    public var current: BudgetPeriodFigures
    /// Whole days to the next period, or to the start day before the budget starts.
    public var daysUntilNextPeriod: Int
    /// None of its categories is left (a delete dropped them all). It's kept, shows an empty state and isn't
    /// counted in the overspent badge (D307.5).
    public var hasNoCategories: Bool

    public init(
        budget: Budget,
        current: BudgetPeriodFigures,
        daysUntilNextPeriod: Int,
        hasNoCategories: Bool = false,
    ) {
        self.budget = budget
        self.current = current
        self.daysUntilNextPeriod = daysUntilNextPeriod
        self.hasNoCategories = hasNoCategories
    }

    public var id: UUID {
        budget.id
    }

    /// Overspent in the current period, for the badge. A budget with no categories never counts (D307.5).
    public var isOverspent: Bool {
        !hasNoCategories && current.state == .overspent
    }
}

/// Budget figures from the ledger (#25, D217).
///
/// - Spent is `CategorySpending`'s net spending in the budget's covered categories and currency: expenses and
///   split lines add, refunds subtract (orphaned ones too), transfers and other income never count.
/// - A transaction counts in the period containing its own calendar day, future-dated ones included (S28).
/// - Carry-over runs from the first period, each with its own limit, so a past period's carry-over uses that
///   period's limit and a shorter period isn't pro-rated (S51, S62).
public enum BudgetProgress {
    /// The share of what's available at which a budget is near its limit.
    public static let nearLimitShare = Decimal(string: "0.9")!

    /// The figures for the period at `index`.
    public static func figures(
        of budget: Budget,
        period index: Int,
        in snapshot: LedgerSnapshot,
    ) -> BudgetPeriodFigures {
        let schedule = budget.schedule
        let index = max(0, index)
        let target = schedule.period(index)
        let covered = BudgetCategories.covered(by: budget, in: snapshot)
        var net = [Decimal](repeating: 0, count: index + 1)
        var excluded: Set<String> = []
        for entry in CategorySpending.entries(in: snapshot, from: budget.startDay, through: target.end) {
            guard let categoryID = entry.categoryID, covered.contains(categoryID) else {
                continue
            }
            if entry.currencyCode != budget.currencyCode {
                if target.contains(entry.day) {
                    excluded.insert(entry.currencyCode)
                }
                continue
            }
            guard let period = schedule.period(containing: entry.day) else {
                continue
            }
            net[period.index] += entry.amount
        }
        let limits = budget.orderedLimits
        var carriedIn: Decimal = 0
        for earlier in 0..<index {
            let limit = Budget.limit(forPeriodStartingOn: schedule.start(ofPeriod: earlier), in: limits)
            let figures = BudgetFigures(budget: limit, netSpending: net[earlier], carriedOver: carriedIn)
            carriedIn = carriedForward(from: figures, of: budget)
        }
        let limit = Budget.limit(forPeriodStartingOn: target.start, in: limits)
        let figures = BudgetFigures(budget: limit, netSpending: net[index], carriedOver: carriedIn)
        return BudgetPeriodFigures(
            period: target,
            limit: limit,
            figures: figures,
            carriedForward: carriedForward(from: figures, of: budget),
            state: state(of: figures),
            excludedCurrencies: excluded.sorted(),
            hasNoAccountInCurrency: !snapshot.accountsVisible().contains { $0.currencyCode == budget.currencyCode },
        )
    }

    /// The budget's current period on `today`, or its first period, not started, before its start day.
    public static func summary(of budget: Budget, today: CalendarDay, in snapshot: LedgerSnapshot) -> BudgetSummary {
        let schedule = budget.schedule
        let hasNoCategories = BudgetCategories.covered(by: budget, in: snapshot).isEmpty
        guard let period = schedule.period(containing: today) else {
            var first = figures(of: budget, period: 0, in: snapshot)
            first.state = .notStarted
            return BudgetSummary(
                budget: budget,
                current: first,
                daysUntilNextPeriod: schedule.daysUntilNextPeriod(today: today),
                hasNoCategories: hasNoCategories,
            )
        }
        return BudgetSummary(
            budget: budget,
            current: figures(of: budget, period: period.index, in: snapshot),
            daysUntilNextPeriod: schedule.daysUntilNextPeriod(today: today),
            hasNoCategories: hasNoCategories,
        )
    }

    /// Overspent when net spending is more than what's available, so with less than 0 available it's overspent
    /// from the first day even with nothing spent; exactly 0 available with nothing spent isn't (D307.2). Near the
    /// limit from 90% of a positive amount available.
    public static func state(of figures: BudgetFigures) -> BudgetState {
        if figures.netSpending > figures.available {
            return .overspent
        }
        if figures.available > 0 && figures.netSpending >= figures.available * nearLimitShare {
            return .nearLimit
        }
        return .onTrack
    }

    private static func carriedForward(from figures: BudgetFigures, of budget: Budget) -> Decimal {
        let remaining = figures.remaining
        if remaining > 0 {
            return budget.carriesOverUnspent ? remaining : 0
        }
        if remaining < 0 {
            return budget.carriesOverOverspending ? remaining : 0
        }
        return 0
    }
}
