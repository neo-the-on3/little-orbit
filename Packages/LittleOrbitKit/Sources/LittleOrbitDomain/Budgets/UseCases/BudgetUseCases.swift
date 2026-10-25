import Foundation

// The budget use cases (#25). View models depend only on these protocols, injected through their initializers.
// `DefaultBudgetUseCases` holds the logic and depends on `BudgetRepository`; the ledger rules are in `LedgerBook`
// and the figures in `BudgetProgress`. "Today" is the device's calendar day (`TransactionTiming.today`).

@MainActor
public protocol ListBudgetsUseCase {
    /// Every budget with its current period, sorted by name (#25).
    func budgets(today: CalendarDay) throws -> [BudgetSummary]
    /// How many budgets are overspent in their current period, for the badge. Exactly at the limit doesn't count,
    /// and neither does a budget with no categories left (D307.5).
    func overspentCount(today: CalendarDay) throws -> Int
}

@MainActor
public protocol BudgetPeriodsUseCase {
    /// One budget with its current period, or its first period before it starts.
    func summary(of budgetID: UUID, today: CalendarDay) throws -> BudgetSummary
    /// The figures for the budget's period at `index`, for moving to earlier and later periods.
    func figures(of budgetID: UUID, period index: Int) throws -> BudgetPeriodFigures
}

@MainActor
public protocol SaveBudgetUseCase {
    /// Adds a budget, or saves the edits to one. A new budget's limit applies from its first period. A changed
    /// limit on an existing budget applies from the period containing `today` on, and earlier periods keep
    /// theirs (#25 AC 4). Throws the ledger's errors, e.g. `budgetLimitNotPositive` for an empty limit.
    @discardableResult
    func save(_ draft: BudgetDraft, today: CalendarDay) throws -> Budget
}

@MainActor
public protocol ChangeBudgetLimitUseCase {
    /// Sets the limit from the period containing `today` on (from the first period before the budget starts).
    func changeLimit(of budgetID: UUID, to amount: Decimal, today: CalendarDay) throws
}

@MainActor
public protocol DeleteBudgetUseCase {
    /// Removes the budget and its history. Transactions are kept (#25).
    func delete(_ budgetID: UUID) throws
}

/// Every budget use case, which `DefaultBudgetUseCases` implements in one type.
public typealias BudgetUseCase = ListBudgetsUseCase & BudgetPeriodsUseCase & SaveBudgetUseCase
    & ChangeBudgetLimitUseCase & DeleteBudgetUseCase

@MainActor
public final class DefaultBudgetUseCases: BudgetUseCase {
    private let repository: any BudgetRepository
    private let now: @MainActor () -> Date

    public init(repository: any BudgetRepository, now: @escaping @MainActor () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
    }

    public func budgets(today: CalendarDay) throws -> [BudgetSummary] {
        let ledger = try repository.budgetLedger()
        return ledger.budgetsVisible()
            .sorted { lhs, rhs in
                let byName = lhs.name.localizedStandardCompare(rhs.name)
                if byName != .orderedSame {
                    return byName == .orderedAscending
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map { BudgetProgress.summary(of: $0, today: today, in: ledger) }
    }

    public func overspentCount(today: CalendarDay) throws -> Int {
        try budgets(today: today).filter(\.isOverspent).count
    }

    public func summary(of budgetID: UUID, today: CalendarDay) throws -> BudgetSummary {
        let ledger = try repository.budgetLedger()
        return BudgetProgress.summary(of: try budget(budgetID, in: ledger), today: today, in: ledger)
    }

    public func figures(of budgetID: UUID, period index: Int) throws -> BudgetPeriodFigures {
        let ledger = try repository.budgetLedger()
        return BudgetProgress.figures(of: try budget(budgetID, in: ledger), period: index, in: ledger)
    }

    @discardableResult
    public func save(_ draft: BudgetDraft, today: CalendarDay) throws -> Budget {
        let ledger = try repository.budgetLedger()
        let limit = draft.limit ?? 0
        var budget: Budget
        if let id = draft.id {
            budget = try self.budget(id, in: ledger)
        } else {
            budget = Budget(startDay: draft.startDay, createdAt: now())
        }
        budget.name = draft.name
        budget.currencyCode = draft.currencyCode
        budget.categoryIDs = draft.categoryIDs
        budget.startDay = draft.startDay
        budget.recurrence = draft.recurrence
        budget.carriesOverUnspent = draft.carriesOverUnspent
        budget.carriesOverOverspending = draft.carriesOverOverspending
        let periodStart = budget.schedule.currentOrFirstPeriod(today: today).start
        if draft.id == nil {
            budget.limits = [BudgetLimit(startDay: draft.startDay, amount: limit, createdAt: now())]
        } else if budget.limits.isEmpty || budget.limit(forPeriodStartingOn: periodStart) != limit {
            budget.limits =
                budget.limits.filter { $0.startDay < periodStart } + [
                    BudgetLimit(startDay: periodStart, amount: limit, createdAt: now())
                ]
        }
        try repository.saveBudget(budget)
        return try self.budget(budget.id, in: repository.budgetLedger())
    }

    public func changeLimit(of budgetID: UUID, to amount: Decimal, today: CalendarDay) throws {
        let budget = try budget(budgetID, in: repository.budgetLedger())
        let periodStart = budget.schedule.currentOrFirstPeriod(today: today).start
        try repository.changeBudgetLimit(of: budgetID, to: amount, fromPeriodStartingOn: periodStart)
    }

    public func delete(_ budgetID: UUID) throws {
        try repository.deleteBudget(id: budgetID)
    }

    private func budget(_ id: UUID, in ledger: LedgerSnapshot) throws -> Budget {
        guard let budget = ledger.budgetsVisible().first(where: { $0.id == id }) else {
            throw LedgerValidationError.missingBudget
        }
        return budget
    }
}
