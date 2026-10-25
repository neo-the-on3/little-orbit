import Foundation

// Budgets (#25): save, change the limit and delete. Category delete and merge update the budgets that picked
// those categories in `LedgerBook.reassignReferences`.

extension LedgerBook {
    /// Adds or replaces a budget.
    ///
    /// Throws, and changes nothing, when:
    /// - the trimmed name is empty or too long (`invalidName`, `nameTooLong`);
    /// - the currency isn't known (`invalidCurrencyCode`);
    /// - there's no limit, or one is 0 or less (`budgetLimitNotPositive`), or has more decimals than the currency
    ///   (`tooManyDecimalPlaces`);
    /// - no categories are picked (`budgetCategoriesRequired`), one isn't in the ledger (`missingCategory`) or
    ///   isn't an expense category (`categoryKindMismatch`). Archived categories can stay picked;
    /// - a custom repeat isn't every 1–99 (`budgetRecurrenceOutOfRange`);
    /// - another live budget has the same trimmed name, ignoring case (`duplicateBudgetName`, D307.6).
    ///
    /// The name is trimmed, the categories are kept once each, and limits from before the start day become one
    /// limit from the start day.
    public static func savingBudget(_ budget: Budget, in snapshot: LedgerSnapshot, now: Date) throws -> LedgerSnapshot {
        let budget = normalize(budget)
        try validate(budget, in: snapshot)
        return try storing(budget, in: snapshot, now: now)
    }

    /// Puts back a version of a budget the ledger held before, for Undo and Redo (D307.8, D310.2). It's
    /// `savingBudget(_:in:now:)` under the stored-budget rule instead of the form's: a version with no categories
    /// is put back exactly, because a category delete can leave a budget like that (D307.5). Every other rule
    /// still applies, so it throws, and changes nothing, for a bad field, a category that isn't live or isn't an
    /// expense category, another live budget with the same name (`duplicateBudgetName`) or a deleted budget.
    /// Like `savingBudget(_:in:now:)`, it doesn't check that limit IDs are unique across budgets, which
    /// `validateStoredBudgets(in:)` does; a version from Undo or Redo only carries its own budget's limits.
    public static func restoringBudget(_ budget: Budget, in snapshot: LedgerSnapshot, now: Date) throws
        -> LedgerSnapshot
    {
        let budget = normalize(budget)
        try validateStored(budget, in: snapshot)
        return try storing(budget, in: snapshot, now: now)
    }

    /// The name clash and deleted-budget checks every write shares, then the write.
    private static func storing(_ budget: Budget, in snapshot: LedgerSnapshot, now: Date) throws -> LedgerSnapshot {
        var budget = budget
        guard budgetNameClash(budget.name, excluding: budget.id, in: snapshot) == nil else {
            throw LedgerValidationError.duplicateBudgetName
        }
        if let existing = snapshot.budgets.first(where: { $0.id == budget.id }) {
            guard existing.deletedAt == nil else {
                throw LedgerValidationError.missingBudget
            }
            budget.createdAt = existing.createdAt
            budget.updatedAt = now
        }
        var snapshot = snapshot
        replaceOrAppend(&snapshot.budgets, with: budget)
        return snapshot
    }

    /// Sets the limit from the period starting on `periodStart` on. Earlier periods keep their limits; later
    /// changes are replaced (#25 AC 4).
    public static func changingBudgetLimit(
        of budgetID: UUID,
        to amount: Decimal,
        fromPeriodStartingOn periodStart: CalendarDay,
        in snapshot: LedgerSnapshot,
        now: Date,
    ) throws -> LedgerSnapshot {
        guard var budget = snapshot.budgets.first(where: { $0.id == budgetID && $0.deletedAt == nil }) else {
            throw LedgerValidationError.missingBudget
        }
        budget.limits =
            budget.limits.filter { $0.startDay < periodStart } + [
                BudgetLimit(startDay: periodStart, amount: amount, createdAt: now)
            ]
        return try savingBudget(budget, in: snapshot, now: now)
    }

    /// Removes a budget with its limit history. Transactions aren't touched (#25).
    public static func deletingBudget(id: UUID, in snapshot: LedgerSnapshot) throws -> LedgerSnapshot {
        guard snapshot.budgets.contains(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw LedgerValidationError.missingBudget
        }
        var snapshot = snapshot
        snapshot.budgets.removeAll { $0.id == id }
        return snapshot
    }

    static func normalize(_ budget: Budget) -> Budget {
        var budget = budget
        budget.name = LedgerText.trimmed(budget.name)
        budget.categoryIDs = Budget.normalizedCategoryIDs(budget.categoryIDs)
        var limits: [BudgetLimit] = []
        // Stable by start day; for the same day, the later entry wins.
        for limit in budget.limits.enumerated()
            .sorted(by: { lhs, rhs in
                lhs.element.startDay != rhs.element.startDay
                    ? lhs.element.startDay < rhs.element.startDay : lhs.offset < rhs.offset
            })
        {
            var limit = limit.element
            if limit.startDay < budget.startDay {
                limit.startDay = budget.startDay
            }
            if limits.last?.startDay == limit.startDay {
                limits.removeLast()
            }
            limits.append(limit)
        }
        budget.limits = limits
        return budget
    }

    /// The other live budget whose trimmed name matches `name`, ignoring case, or `nil` (D307.6). It's the one name
    /// rule: every write refuses a clash with it, and Undo and Redo check it before writing so a clash goes stale
    /// instead of failing every time (D310.1).
    static func budgetNameClash(_ name: String, excluding id: UUID, in snapshot: LedgerSnapshot) -> Budget? {
        let key = LedgerText.nameKey(name)
        return snapshot.budgetsVisible().first { $0.id != id && LedgerText.nameKey($0.name) == key }
    }

    /// The one rule for budgets that come from outside the app's own changes, a restored backup today (#174 B1).
    /// Both stores' `replaceLedger` run it before anything is replaced, and the backup decoder runs it so such a
    /// backup is damaged before a restore starts. Throws, and changes nothing, when any budget:
    /// - has an empty or too long name, or an unknown currency;
    /// - has a start day or limit day that isn't a real calendar day;
    /// - has no limit, a limit of 0 or less, or one with more decimals than its currency;
    /// - picks a category that isn't live in `snapshot`, or isn't an expense category;
    /// - repeats by a custom count outside 1–99, so a step below 1 never reaches the period lookup;
    /// - shares its ID with another budget, or a limit's ID with another limit.
    ///
    /// A budget with no categories is valid: a category delete can leave one like that, and it's kept (D307.5).
    /// Names aren't checked for clashes, so the rule stays what the stores need to agree, not a form rule.
    public static func validateStoredBudgets(in snapshot: LedgerSnapshot) throws {
        var budgetIDs: Set<UUID> = []
        var limitIDs: Set<UUID> = []
        for budget in snapshot.budgets {
            guard budgetIDs.insert(budget.id).inserted else {
                throw LedgerValidationError.duplicateBudgetID
            }
            for limit in budget.limits {
                guard limitIDs.insert(limit.id).inserted else {
                    throw LedgerValidationError.duplicateBudgetID
                }
            }
            try validateStored(budget, in: snapshot)
        }
    }

    /// One budget under the stored-budget rule: its fields and its categories, which may be none (D307.5).
    private static func validateStored(_ budget: Budget, in snapshot: LedgerSnapshot) throws {
        try validateFields(of: budget)
        try validateCategories(budget.categoryIDs, in: snapshot)
    }

    static func validate(_ budget: Budget, in snapshot: LedgerSnapshot) throws {
        try validateFields(of: budget)
        guard !budget.categoryIDs.isEmpty else {
            throw LedgerValidationError.budgetCategoriesRequired
        }
        try validateCategories(budget.categoryIDs, in: snapshot)
    }

    private static func validateFields(of budget: Budget) throws {
        try LedgerText.validateName(budget.name)
        guard CurrencyCode.minorUnits(for: budget.currencyCode) != nil else {
            throw LedgerValidationError.invalidCurrencyCode
        }
        guard budget.startDay.isRealDay, budget.limits.allSatisfy(\.startDay.isRealDay) else {
            throw LedgerValidationError.invalidBudgetDay
        }
        guard !budget.limits.isEmpty else {
            throw LedgerValidationError.budgetLimitNotPositive
        }
        for limit in budget.limits {
            guard limit.amount > 0 else {
                throw LedgerValidationError.budgetLimitNotPositive
            }
            try MinorUnitDecimal.validate(limit.amount, currencyCode: budget.currencyCode)
        }
        guard budget.recurrence.isValid else {
            throw LedgerValidationError.budgetRecurrenceOutOfRange
        }
    }

    private static func validateCategories(_ ids: [UUID], in snapshot: LedgerSnapshot) throws {
        for id in ids {
            guard let category = activeCategory(id, in: snapshot) else {
                throw LedgerValidationError.missingCategory
            }
            guard category.kind == .expense else {
                throw LedgerValidationError.categoryKindMismatch
            }
        }
    }
}

extension Budget {
    /// Each category once, in a fixed order, so the same pick always compares and stores the same.
    public static func normalizedCategoryIDs(_ ids: [UUID]) -> [UUID] {
        Array(Set(ids)).sorted { $0.uuidString < $1.uuidString }
    }
}

extension CalendarDay {
    /// A day that exists in the proleptic Gregorian calendar, in years 1–9999: no 30 Feb or month 13.
    var isRealDay: Bool {
        (1...9_999).contains(year) && (1...12).contains(month)
            && (1...Self.daysInMonth(year: year, month: month)).contains(day)
    }
}
