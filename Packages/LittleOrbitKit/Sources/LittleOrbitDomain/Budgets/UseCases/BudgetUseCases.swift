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

/// Budget saves as revertible changes, for the window's Undo and Redo (D307.8).
@MainActor
public protocol BudgetChangesUseCase {
    /// Saves like `SaveBudgetUseCase.save(_:today:)` and returns the change: `.added` for a new budget, or
    /// `.replaced` with the version before the edit.
    func savedChange(_ draft: BudgetDraft, today: CalendarDay) throws -> BudgetChange
    /// Changes the limit like `ChangeBudgetLimitUseCase.changeLimit(of:to:today:)` and returns the change,
    /// `.replaced` with the version before it (Change Budget Limit, the detail's action sheet).
    func limitChange(of budgetID: UUID, to amount: Decimal, today: CalendarDay) throws -> BudgetChange
    /// What `change` left in the ledger, read right after it was made or reverted, for the stale check.
    func outcome(of change: BudgetChange) throws -> BudgetChangeOutcome
    /// Reverts `change` if the ledger still holds `outcome`, by value; otherwise writes nothing and says why
    /// (D187.5, D307.8). The check runs first, so a stale step never writes.
    func revert(_ change: BudgetChange, expecting outcome: BudgetChangeOutcome) throws -> BudgetRevertResult
}

/// Every budget use case, which `DefaultBudgetUseCases` implements in one type.
public typealias BudgetUseCase = ListBudgetsUseCase & BudgetPeriodsUseCase & SaveBudgetUseCase
    & ChangeBudgetLimitUseCase & DeleteBudgetUseCase & BudgetChangesUseCase

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
        let id = try write(draft, today: today)
        return try budget(id, in: repository.budgetLedger())
    }

    /// Saves the draft and returns the budget's ID, without reading it back.
    @discardableResult
    private func write(_ draft: BudgetDraft, today: CalendarDay) throws -> UUID {
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
        return budget.id
    }

    public func changeLimit(of budgetID: UUID, to amount: Decimal, today: CalendarDay) throws {
        let budget = try budget(budgetID, in: repository.budgetLedger())
        let periodStart = budget.schedule.currentOrFirstPeriod(today: today).start
        try repository.changeBudgetLimit(of: budgetID, to: amount, fromPeriodStartingOn: periodStart)
    }

    public func delete(_ budgetID: UUID) throws {
        try repository.deleteBudget(id: budgetID)
    }

    // MARK: Changes for Undo (D307.8)

    /// Nothing is read back after the write, so a read that fails then can't make a saved budget look unsaved;
    /// the step's `outcome(of:)` read finds that instead (#176 review NB3).
    public func savedChange(_ draft: BudgetDraft, today: CalendarDay) throws -> BudgetChange {
        if let id = draft.id {
            let previous = try budget(id, in: repository.budgetLedger())
            try write(draft, today: today)
            return .replaced(previous)
        }
        return .added(try write(draft, today: today))
    }

    public func limitChange(of budgetID: UUID, to amount: Decimal, today: CalendarDay) throws -> BudgetChange {
        let previous = try budget(budgetID, in: repository.budgetLedger())
        try changeLimit(of: budgetID, to: amount, today: today)
        return .replaced(previous)
    }

    public func outcome(of change: BudgetChange) throws -> BudgetChangeOutcome {
        BudgetChangeOutcome(budget: try current(change.budgetID))
    }

    public func revert(_ change: BudgetChange, expecting outcome: BudgetChangeOutcome) throws -> BudgetRevertResult {
        if let reason = try staleReason(change, expecting: outcome) {
            return .stale(reason)
        }
        let inverse: BudgetChange
        switch change {
        case .added(let id):
            let removed = try budget(id, in: repository.budgetLedger())
            try repository.deleteBudget(id: id)
            inverse = .removed(removed)
        case .replaced(let previous):
            let replaced = try budget(previous.id, in: repository.budgetLedger())
            try repository.restoreBudget(previous)
            inverse = .replaced(replaced)
        case .removed(let budget):
            try repository.restoreBudget(budget)
            inverse = .added(budget.id)
        }
        return .reverted(inverse, try self.outcome(of: inverse))
    }

    /// The budget as stored now, or `nil` when there's none with that ID.
    private func current(_ id: UUID) throws -> Budget? {
        try repository.budgetLedger().budgetsVisible().first { $0.id == id }
    }

    /// A deleted budget, a category the revert would put back that's gone, a budget that no longer holds what the
    /// step left, or a name another budget has taken since, in that order: a category delete also changes the
    /// budget, and naming the category says more (D307.8). A version with no categories isn't stale; it's put
    /// back exactly (D310.2).
    ///
    /// Two refusals the ledger could still repeat every time aren't checked here, because neither can happen today,
    /// so they'd reach the revert as a failure that keeps the step:
    /// - `categoryKindMismatch`: a category's kind can't change in the editor, and replacing the ledger clears the
    ///   history;
    /// - `missingBudget` for a soft-deleted record: budget deletes are hard.
    ///
    /// Whoever adds category kind changes or sync should make those stale here too.
    private func staleReason(_ change: BudgetChange, expecting outcome: BudgetChangeOutcome) throws
        -> BudgetStaleReason?
    {
        let ledger = try repository.budgetLedger()
        let now = ledger.budgetsVisible().first { $0.id == change.budgetID }
        let restoring: Budget?
        switch change {
        case .added:
            guard let now else {
                return .budgetDeleted
            }
            return outcome.budget.map(now.hasSameSettings) == true ? nil : .budgetChanged
        case .replaced(let previous):
            guard now != nil else {
                return .budgetDeleted
            }
            restoring = previous
        case .removed(let budget):
            guard now == nil else {
                return .budgetChanged
            }
            restoring = budget
        }
        let live = Set(ledger.categories.filter { $0.deletedAt == nil }.map(\.id))
        if let gone = restoring?.categoryIDs.first(where: { !live.contains($0) }) {
            return .categoryDeleted(gone)
        }
        if case .replaced = change, let now, outcome.budget.map(now.hasSameSettings) != true {
            return .budgetChanged
        }
        // The ledger refuses a clash every time, so it's checked before anything is written (D310.1).
        guard let restoring else {
            return nil
        }
        return LedgerBook.budgetNameClash(restoring.name, excluding: restoring.id, in: ledger)
            .map { .nameTaken($0.name) }
    }

    private func budget(_ id: UUID, in ledger: LedgerSnapshot) throws -> Budget {
        guard let budget = ledger.budgetsVisible().first(where: { $0.id == id }) else {
            throw LedgerValidationError.missingBudget
        }
        return budget
    }
}
