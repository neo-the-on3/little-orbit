import Foundation

/// One revertible change to a budget, for Undo and Redo (D307.8). Reverting a change returns its inverse, which
/// reverts it in turn. The window's history keeps the changes (D187.2).
public enum BudgetChange: Equatable, Sendable {
    /// Revert by deleting this new budget (Undo New Budget).
    case added(UUID)
    /// Revert by saving this earlier version back, limit history included (Undo Edit Budget, Undo Change Budget
    /// Limit).
    case replaced(Budget)
    /// Revert by putting this budget back with the same ID, categories and limit history (Redo New Budget).
    case removed(Budget)

    /// The budget the change is about.
    public var budgetID: UUID {
        switch self {
        case .added(let id): id
        case .replaced(let budget), .removed(let budget): budget.id
        }
    }
}

/// What a budget change left in the ledger, read right after it, for the stale check (D187.5, D307.8). `nil`
/// when the change left no budget, after a delete.
public struct BudgetChangeOutcome: Equatable, Sendable {
    public var budget: Budget?

    public init(budget: Budget?) {
        self.budget = budget
    }
}

/// Why a budget step can't be reverted any more (D307.8, D228.5). Facts only; the caller words them.
public enum BudgetStaleReason: Equatable, Sendable {
    /// The budget was changed since the step: a field the user sets differs, or a deleted budget is back.
    case budgetChanged
    /// The budget was deleted since the step.
    case budgetDeleted
    /// Reverting would put back a category that has been deleted since (the D306 amendment's pattern).
    case categoryDeleted(UUID)
    /// Reverting would give the budget a name another live budget has taken since, trimmed and ignoring case. It
    /// holds that budget's stored name. The ledger would refuse the write every time, so it's stale, not a
    /// failure (D310.1).
    case nameTaken(String)
}

/// What reverting a budget change did: reverted it, returning its inverse and what that left, or found it stale
/// and wrote nothing.
public enum BudgetRevertResult: Equatable, Sendable {
    case reverted(BudgetChange, BudgetChangeOutcome)
    case stale(BudgetStaleReason)
}

extension Budget {
    /// Whether two versions hold the same values in every field the user sets: the name, currency, categories,
    /// start day, repeat, carry-over and the limit history by day and amount. Bookkeeping dates and IDs aren't
    /// compared, so the stale check is by value (D187.5).
    public func hasSameSettings(as other: Budget) -> Bool {
        func limits(_ budget: Budget) -> [BudgetLimitValue] {
            budget.orderedLimits.map { BudgetLimitValue(startDay: $0.startDay, amount: $0.amount) }
        }
        return name == other.name && currencyCode == other.currencyCode
            && Set(categoryIDs) == Set(other.categoryIDs) && startDay == other.startDay
            && recurrence == other.recurrence && carriesOverUnspent == other.carriesOverUnspent
            && carriesOverOverspending == other.carriesOverOverspending && limits(self) == limits(other)
    }

    /// Whether the budget has a period that ended before `today`, so its past figures exist (D307.7).
    public func hasPastPeriods(today: CalendarDay) -> Bool {
        (schedule.period(containing: today)?.index ?? 0) > 0
    }
}

private struct BudgetLimitValue: Equatable {
    var startDay: CalendarDay
    var amount: Decimal
}

extension BudgetDraft {
    /// Whether saving this edit of `budget` recalculates past periods, so the form asks “Recalculate Past
    /// Periods?” first (D307.7): the start day or the repeat changes, and the budget has a period that ended
    /// before `today`. A new budget, or one with no past periods, saves without asking.
    public func recalculatesPastPeriods(of budget: Budget, today: CalendarDay) -> Bool {
        guard id == budget.id else {
            return false
        }
        return (startDay != budget.startDay || recurrence != budget.recurrence) && budget.hasPastPeriods(today: today)
    }
}
