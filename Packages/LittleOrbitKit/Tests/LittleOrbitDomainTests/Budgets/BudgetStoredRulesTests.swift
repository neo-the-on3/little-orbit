import Foundation
import LittleOrbitDomain
import Testing

/// The one rule for budgets from outside the app's own changes, a restored backup today (#174 B1), and the backup
/// shape of a budget's repeat and days (#174 review NB1).
@Suite("Budgets from a backup (#174 B1)")
struct BudgetStoredRulesTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias B = BudgetFixture  // swiftlint:disable:this type_name

    private let now = F.date(2026, 11, 5)

    private func ledger(_ budgets: [Budget]) -> LedgerSnapshot {
        var ledger = B.ledger
        ledger.budgets = budgets
        return ledger
    }

    private func refuses(_ error: LedgerValidationError, _ change: (inout Budget) -> Void) {
        var budget = B.budget()
        change(&budget)
        #expect(throws: error) { try LedgerBook.validateStoredBudgets(in: ledger([budget])) }
    }

    @Test("A budget the app saved passes, and so does one a category delete left with no categories (D307.5)")
    func validBudgets() throws {
        try LedgerBook.validateStoredBudgets(in: ledger([B.budget(), B.budget("Empty", categories: [])]))
        let archived = try LedgerBook.archivingCategory(id: B.restaurantsID, archived: true, in: B.ledger, now: now)
        var withArchived = archived
        withArchived.budgets = [B.budget()]
        try LedgerBook.validateStoredBudgets(in: withArchived)
    }

    @Test("A missing or removed category is refused")
    func missingCategory() {
        refuses(.missingCategory) { $0.categoryIDs = [UUID()] }
        var removed = B.ledger
        removed.categories[0].deletedAt = now
        removed.budgets = [B.budget(categories: [B.foodID])]
        #expect(throws: LedgerValidationError.missingCategory) { try LedgerBook.validateStoredBudgets(in: removed) }
    }

    @Test("An income category is refused")
    func incomeCategory() {
        refuses(.categoryKindMismatch) { $0.categoryIDs = [B.restaurantsID, B.salaryID] }
    }

    @Test("A limit of 0 or less, no limit, or too many decimals is refused")
    func limits() {
        refuses(.budgetLimitNotPositive) { $0.limits[0].amount = 0 }
        refuses(.budgetLimitNotPositive) { $0.limits[0].amount = -500 }
        refuses(.budgetLimitNotPositive) { $0.limits = [] }
        refuses(.budgetLimitNotPositive) {
            $0.limits.append(BudgetLimit(startDay: F.day(2026, 12, 1), amount: 0, createdAt: now))
        }
        refuses(.tooManyDecimalPlaces) { $0.limits[0].amount = Decimal(string: "10.005")! }
    }

    @Test("A custom repeat below 1 or above 99 is refused")
    func repeatCount() {
        for count in [0, -1, 100] {
            refuses(.budgetRecurrenceOutOfRange) { $0.recurrence = .custom(every: count, unit: .day) }
        }
    }

    @Test("An unknown currency, an empty name, a day that doesn't exist or a repeated ID is refused")
    func otherDamage() {
        refuses(.invalidCurrencyCode) { $0.currencyCode = "ZZZ" }
        refuses(.invalidName) { $0.name = "" }
        refuses(.invalidBudgetDay) { $0.startDay = CalendarDay(year: 2026, month: 2, day: 30) }
        refuses(.invalidBudgetDay) { $0.limits[0].startDay = CalendarDay(year: 2026, month: 13, day: 1) }
        let budget = B.budget()
        var twin = B.budget("Other")
        twin.id = budget.id
        #expect(throws: LedgerValidationError.duplicateBudgetID) {
            try LedgerBook.validateStoredBudgets(in: ledger([budget, twin]))
        }
        var sharedLimit = B.budget("Other")
        sharedLimit.limits[0].id = budget.limits[0].id
        #expect(throws: LedgerValidationError.duplicateBudgetID) {
            try LedgerBook.validateStoredBudgets(in: ledger([budget, sharedLimit]))
        }
    }

    @Test(
        "A step of 0 or less can't hang the period lookup, the figures or the list",
        .timeLimit(.minutes(1)),
    )
    func stepBelowOneTerminates() {
        for count in [0, -3] {
            let budget = B.budget(recurrence: .custom(every: count, unit: .month))
            let far = F.day(2099, 12, 31)
            #expect(budget.schedule.period(containing: far) == nil)
            #expect(budget.schedule.period(containing: budget.startDay) == nil)
            let summary = BudgetProgress.summary(of: budget, today: far, in: ledger([budget]))
            #expect(summary.current.state == .notStarted)
            _ = BudgetProgress.figures(of: budget, period: 3, in: ledger([budget]))
        }
    }

    @Test("NB1: the repeat is written in the store's shape and days as year, month and day")
    func backupShape() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let custom = try encoder.encode(BudgetRecurrence.custom(every: 3, unit: .week))
        #expect(custom == Data(#"{"count":3,"kind":"custom","unit":"week"}"#.utf8))
        let monthly = try encoder.encode(BudgetRecurrence.monthly)
        #expect(monthly == Data(#"{"kind":"monthly"}"#.utf8))
        let fortnightly = try encoder.encode(BudgetRecurrence.fortnightly)
        #expect(fortnightly == Data(#"{"kind":"fortnightly"}"#.utf8))
        let day = try encoder.encode(CalendarDay(year: 2027, month: 1, day: 31))
        #expect(day == Data(#"{"day":31,"month":1,"year":2027}"#.utf8))
        for recurrence in [BudgetRecurrence.weekly, .fortnightly, .monthly, .yearly, .custom(every: 99, unit: .day)] {
            #expect(try JSONDecoder().decode(BudgetRecurrence.self, from: encoder.encode(recurrence)) == recurrence)
        }
    }

    @Test("NB1: a repeat with an unknown kind or unit, or a custom one without its count, doesn't decode")
    func unknownRepeat() {
        for json in [
            #"{"kind":"daily"}"#, #"{"kind":"custom","unit":"hour","count":2}"#, #"{"kind":"custom","unit":"day"}"#,
        ] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(BudgetRecurrence.self, from: Data(json.utf8))
            }
        }
    }
}
