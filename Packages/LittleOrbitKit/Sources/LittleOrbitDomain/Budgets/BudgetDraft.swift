import Foundation

/// What the new and edit budget form holds (#25).
public struct BudgetDraft: Equatable, Sendable {
    /// `nil` for a new budget.
    public var id: UUID?
    public var name: String
    /// The limit for the current period on; `nil` while the field is empty or can't be read.
    public var limit: Decimal?
    public var currencyCode: String
    public var categoryIDs: [UUID]
    public var startDay: CalendarDay
    public var recurrence: BudgetRecurrence
    public var carriesOverUnspent: Bool
    public var carriesOverOverspending: Bool

    public init(
        id: UUID? = nil,
        name: String = "",
        limit: Decimal? = nil,
        currencyCode: String,
        categoryIDs: [UUID] = [],
        startDay: CalendarDay,
        recurrence: BudgetRecurrence = .monthly,
        carriesOverUnspent: Bool = false,
        carriesOverOverspending: Bool = false,
    ) {
        self.id = id
        self.name = name
        self.limit = limit
        self.currencyCode = currencyCode
        self.categoryIDs = categoryIDs
        self.startDay = startDay
        self.recurrence = recurrence
        self.carriesOverUnspent = carriesOverUnspent
        self.carriesOverOverspending = carriesOverOverspending
    }

    /// The form for an existing budget, showing the limit of the period containing `today`.
    public init(editing budget: Budget, today: CalendarDay) {
        self.init(
            id: budget.id,
            name: budget.name,
            limit: budget.limit(forPeriodStartingOn: budget.schedule.currentOrFirstPeriod(today: today).start),
            currencyCode: budget.currencyCode,
            categoryIDs: budget.categoryIDs,
            startDay: budget.startDay,
            recurrence: budget.recurrence,
            carriesOverUnspent: budget.carriesOverUnspent,
            carriesOverOverspending: budget.carriesOverOverspending,
        )
    }

    /// What blocks saving, for the form's inline errors. Empty when the draft can be saved, apart from rules
    /// only the ledger can check, such as a deleted category.
    public var problems: Set<BudgetDraftProblem> {
        var problems: Set<BudgetDraftProblem> = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.insert(.nameMissing)
        }
        if (limit ?? 0) <= 0 {
            problems.insert(.limitNotPositive)
        }
        if categoryIDs.isEmpty {
            problems.insert(.noCategories)
        }
        if !recurrence.isValid {
            problems.insert(.recurrenceOutOfRange)
        }
        return problems
    }
}

/// Why a budget draft can't be saved (#25 S18, S19, S16). The presentation layer words them.
public enum BudgetDraftProblem: Hashable, Sendable {
    case nameMissing
    case limitNotPositive
    case noCategories
    case recurrenceOutOfRange
}

extension BudgetSchedule {
    /// The period containing `today`, or the first period before the start day.
    public func currentOrFirstPeriod(today: CalendarDay) -> BudgetPeriod {
        period(containing: today) ?? period(0)
    }
}
