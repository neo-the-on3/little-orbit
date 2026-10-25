import Foundation
import LittleOrbitDomain
import Testing

/// The budget ledger rules (#25): validation, the limit history and delete.
@Suite("Budget ledger rules (#25)")
struct BudgetLedgerRulesTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias B = BudgetFixture  // swiftlint:disable:this type_name

    private let now = F.date(2026, 11, 5)

    private func save(_ budget: Budget, in snapshot: LedgerSnapshot = B.ledger) throws -> LedgerSnapshot {
        try LedgerBook.savingBudget(budget, in: snapshot, now: now)
    }

    @Test("A valid budget is saved with its name trimmed and each category once")
    func savesNormalized() throws {
        var budget = B.budget(categories: [B.shoppingID, B.foodID, B.shoppingID])
        budget.name = "  Eating out \n"
        let saved = try #require(try save(budget).budgets.first)
        #expect(saved.name == "Eating out")
        #expect(Set(saved.categoryIDs) == [B.shoppingID, B.foodID])
        #expect(saved.categoryIDs.count == 2)
    }

    @Test("S18: an empty name, a 0 or −100 limit, or no limit blocks saving")
    func nameAndLimit() throws {
        #expect(throws: LedgerValidationError.invalidName) { try save(B.budget("   ")) }
        #expect(throws: LedgerValidationError.budgetLimitNotPositive) { try save(B.budget(limit: 0)) }
        #expect(throws: LedgerValidationError.budgetLimitNotPositive) { try save(B.budget(limit: -100)) }
        var noLimit = B.budget()
        noLimit.limits = []
        #expect(throws: LedgerValidationError.budgetLimitNotPositive) { try save(noLimit) }
    }

    @Test("S19: no categories, an income category or a removed category blocks saving")
    func categories() throws {
        #expect(throws: LedgerValidationError.budgetCategoriesRequired) { try save(B.budget(categories: [])) }
        #expect(throws: LedgerValidationError.categoryKindMismatch) { try save(B.budget(categories: [B.salaryID])) }
        #expect(throws: LedgerValidationError.missingCategory) { try save(B.budget(categories: [UUID()])) }
    }

    @Test("An archived category can stay picked")
    func archivedCategory() throws {
        let archived = try LedgerBook.archivingCategory(id: B.shoppingID, archived: true, in: B.ledger, now: now)
        #expect(try save(B.budget(categories: [B.shoppingID]), in: archived).budgets.count == 1)
    }

    @Test("S16: a custom repeat of 0 or 100 is refused; 1 and 99 are saved")
    func customRepeat() throws {
        for count in [0, 100] {
            #expect(throws: LedgerValidationError.budgetRecurrenceOutOfRange) {
                try save(B.budget(recurrence: .custom(every: count, unit: .week)))
            }
        }
        for count in [1, 99] {
            #expect(try save(B.budget(recurrence: .custom(every: count, unit: .month))).budgets.count == 1)
        }
    }

    @Test("S8, D17: an unknown currency, or more decimals than the currency has, is refused")
    func currency() throws {
        #expect(throws: LedgerValidationError.invalidCurrencyCode) { try save(B.budget(currency: "XXQ")) }
        #expect(throws: LedgerValidationError.tooManyDecimalPlaces) {
            try save(B.budget(limit: Decimal(string: "50000.5")!, currency: "JPY"))
        }
        #expect(try save(B.budget(limit: 50_000, currency: "JPY")).budgets.first?.currencyCode == "JPY")
    }

    @Test("Editing keeps the created date and stamps the update")
    func editStamps() throws {
        let budget = B.budget()
        var snapshot = try save(budget)
        var edited = budget
        edited.name = "Dining"
        edited.createdAt = .distantPast
        snapshot = try LedgerBook.savingBudget(edited, in: snapshot, now: F.date(2026, 11, 9))
        let saved = try #require(snapshot.budgets.first)
        #expect(saved.createdAt == budget.createdAt)
        #expect(saved.updatedAt == F.date(2026, 11, 9))
        #expect(snapshot.budgets.count == 1)
    }

    @Test("#25 AC 4: a new limit applies from its period on, replacing later changes and keeping earlier ones")
    func limitChange() throws {
        let budget = B.budget(limit: 8_000)
        var snapshot = try save(budget)
        snapshot = try LedgerBook.changingBudgetLimit(
            of: budget.id,
            to: 9_000,
            fromPeriodStartingOn: F.day(2027, 2, 1),
            in: snapshot,
            now: now,
        )
        snapshot = try LedgerBook.changingBudgetLimit(
            of: budget.id,
            to: 10_000,
            fromPeriodStartingOn: F.day(2027, 1, 1),
            in: snapshot,
            now: now,
        )
        let saved = try #require(snapshot.budgets.first)
        #expect(saved.limits.map(\.amount) == [8_000, 10_000])
        #expect(saved.limit(forPeriodStartingOn: F.day(2026, 12, 1)) == 8_000)
        #expect(saved.limit(forPeriodStartingOn: F.day(2027, 3, 1)) == 10_000)
        #expect(throws: LedgerValidationError.budgetLimitNotPositive) {
            try LedgerBook.changingBudgetLimit(
                of: budget.id,
                to: 0,
                fromPeriodStartingOn: F.day(2027, 1, 1),
                in: snapshot,
                now: now,
            )
        }
    }

    @Test("A limit change from the first period replaces the whole history")
    func limitFromStart() throws {
        let budget = B.budget(limit: 8_000)
        let snapshot = try LedgerBook.changingBudgetLimit(
            of: budget.id,
            to: 6_000,
            fromPeriodStartingOn: budget.startDay,
            in: try save(budget),
            now: now,
        )
        #expect(snapshot.budgets.first?.limits.map(\.amount) == [6_000])
    }

    @Test("Limits from before the start day become one limit from the start day")
    func limitsBeforeStart() throws {
        var budget = B.budget(limit: 1_000)
        budget.limits.append(BudgetLimit(startDay: F.day(2026, 10, 1), amount: 2_000))
        budget.limits[0].startDay = F.day(2026, 9, 1)
        let saved = try #require(try save(budget).budgets.first)
        #expect(saved.limits.count == 1)
        #expect(saved.limits.first?.startDay == budget.startDay)
        #expect(saved.limits.first?.amount == 2_000)
    }

    @Test("Delete removes the budget and keeps its transactions; a missing budget throws")
    func delete() throws {
        let budget = B.budget()
        var snapshot = try B.saving([B.expense(100, on: now)], budgets: [budget])
        snapshot = try LedgerBook.deletingBudget(id: budget.id, in: snapshot)
        #expect(snapshot.budgets.isEmpty)
        #expect(snapshot.transactionsVisible().count == 1)
        #expect(throws: LedgerValidationError.missingBudget) {
            try LedgerBook.deletingBudget(id: budget.id, in: snapshot)
        }
        #expect(throws: LedgerValidationError.missingBudget) {
            try LedgerBook.changingBudgetLimit(
                of: budget.id,
                to: 1,
                fromPeriodStartingOn: budget.startDay,
                in: snapshot,
                now: now,
            )
        }
    }

    @Test("Repeat round-trips through its stored values; unknown values read as monthly")
    func storedRecurrence() {
        let all: [BudgetRecurrence] = [
            .weekly, .fortnightly, .monthly, .yearly, .custom(every: 3, unit: .week), .custom(every: 99, unit: .day),
        ]
        for recurrence in all {
            #expect(BudgetRecurrence(recurrence.stored) == recurrence)
        }
        #expect(BudgetRecurrence(.init(kind: "hourly")) == .monthly)
        #expect(BudgetRecurrence(.init(kind: "custom", unit: "decade", count: 2)) == .monthly)
        #expect(BudgetRecurrence(.init(kind: "custom", unit: "week")) == .monthly)
    }
}
