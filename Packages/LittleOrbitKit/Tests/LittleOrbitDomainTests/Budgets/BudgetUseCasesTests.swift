import Foundation
import LittleOrbitDomain
import Testing

/// The budget use cases (#25): the list, the badge count, periods, save, the limit change and delete.
@MainActor
@Suite("Budget use cases (#25)")
struct BudgetUseCasesTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias B = BudgetFixture  // swiftlint:disable:this type_name

    private let today = F.day(2026, 11, 20)
    private let november = F.date(2026, 11, 10)

    private func make(_ budgets: [Budget] = [], _ transactions: [Transaction] = []) throws -> (
        FakeBudgetRepository, DefaultBudgetUseCases
    ) {
        let repository = FakeBudgetRepository(try B.saving(transactions, budgets: budgets))
        return (repository, DefaultBudgetUseCases(repository: repository, now: { F.date(2026, 11, 5) }))
    }

    private func draft(
        _ name: String = "Eating out",
        limit: Decimal? = 8_000,
        categories: [UUID] = [B.restaurantsID],
    ) -> BudgetDraft {
        BudgetDraft(
            name: name,
            limit: limit,
            currencyCode: "INR",
            categoryIDs: categories,
            startDay: F.day(2026, 11, 1),
        )
    }

    @Test("The list is sorted by name and shows each budget's current period")
    func listSorted() throws {
        let (_, useCases) = try make([
            B.budget("travel", categories: [B.travelID]),
            B.budget("Eating out"),
            B.budget("Groceries", categories: [B.groceriesID]),
        ])
        let rows = try useCases.budgets(today: today)
        #expect(rows.map(\.budget.name) == ["Eating out", "Groceries", "travel"])
        #expect(rows.allSatisfy { $0.current.period.start == F.day(2026, 11, 1) })
        #expect(rows.first?.daysUntilNextPeriod == 11)
    }

    @Test("S22, S29, #25 AC 5: the badge counts overspent budgets only")
    func overspentCount() throws {
        let (repository, useCases) = try make([
            B.budget("Eating out", limit: 1_000),
            B.budget("Shopping", limit: 5_000, categories: [B.shoppingID]),
            B.budget("Groceries", limit: 500, categories: [B.groceriesID]),
        ])
        try repository.adding([
            B.expense(1_200, on: november),
            B.expense(5_000, in: B.shoppingID, on: november),
            B.expense(100, in: B.groceriesID, on: november),
        ])
        #expect(try useCases.overspentCount(today: today) == 1)
    }

    @Test("#25 AC 6: progress follows a new expense straight away")
    func updatesImmediately() throws {
        let budget = B.budget()
        let (repository, useCases) = try make([budget])
        #expect(try useCases.summary(of: budget.id, today: today).current.figures.spent == 0)
        try repository.adding([B.expense(450, on: november)])
        #expect(try useCases.summary(of: budget.id, today: today).current.figures.spent == 450)
    }

    @Test("A period's figures can be read for earlier and later periods")
    func periods() throws {
        let budget = B.budget()
        let (_, useCases) = try make([budget], [B.expense(450, on: F.date(2026, 12, 3))])
        #expect(try useCases.figures(of: budget.id, period: 1).figures.spent == 450)
        #expect(try useCases.figures(of: budget.id, period: 1).period.start == F.day(2026, 12, 1))
        #expect(throws: LedgerValidationError.missingBudget) { try useCases.figures(of: UUID(), period: 0) }
    }

    @Test("Save adds a budget with its limit from the first period")
    func saveNew() throws {
        let (repository, useCases) = try make()
        let saved = try useCases.save(draft(), today: today)
        #expect(repository.snapshot.budgets == [saved])
        #expect(saved.limits.map(\.startDay) == [F.day(2026, 11, 1)])
        #expect(saved.limits.map(\.amount) == [8_000])
        #expect(saved.createdAt == F.date(2026, 11, 5))
    }

    @Test("S18, S19: save refuses an empty limit, and the draft lists what blocks it")
    func saveRefused() throws {
        let (repository, useCases) = try make()
        #expect(throws: LedgerValidationError.budgetLimitNotPositive) {
            try useCases.save(draft(limit: nil), today: today)
        }
        #expect(repository.snapshot.budgets.isEmpty)
        #expect(draft(" ", limit: 0, categories: []).problems == [.nameMissing, .limitNotPositive, .noCategories])
        var custom = draft()
        custom.recurrence = .custom(every: 100, unit: .day)
        #expect(custom.problems == [.recurrenceOutOfRange])
        #expect(draft().problems.isEmpty)
    }

    @Test("#25 AC 4, S27: editing the limit applies it from the current period; earlier periods keep theirs")
    func editLimitFromCurrentPeriod() throws {
        let (_, useCases) = try make()
        let saved = try useCases.save(draft(), today: F.day(2026, 11, 2))
        var edit = BudgetDraft(editing: saved, today: F.day(2027, 1, 15))
        #expect(edit.limit == 8_000)
        edit.limit = 10_000
        edit.name = "Dining"
        let edited = try useCases.save(edit, today: F.day(2027, 1, 15))
        #expect(edited.name == "Dining")
        #expect(edited.limits.map(\.amount) == [8_000, 10_000])
        #expect(edited.limits.map(\.startDay) == [F.day(2026, 11, 1), F.day(2027, 1, 1)])
        #expect(edited.createdAt == saved.createdAt)
    }

    @Test("Editing without changing the limit leaves the history alone")
    func editKeepsHistory() throws {
        let (_, useCases) = try make()
        let saved = try useCases.save(draft(), today: today)
        var edit = BudgetDraft(editing: saved, today: F.day(2027, 1, 15))
        edit.carriesOverUnspent = true
        let edited = try useCases.save(edit, today: F.day(2027, 1, 15))
        #expect(edited.limits == saved.limits)
        #expect(edited.carriesOverUnspent)
    }

    @Test("Change limit uses the period containing today, or the first period before the start")
    func changeLimit() throws {
        let budget = B.budget(from: F.day(2027, 1, 31))
        let (repository, useCases) = try make([budget])
        try useCases.changeLimit(of: budget.id, to: 9_000, today: F.day(2027, 3, 5))
        try useCases.changeLimit(of: budget.id, to: 7_000, today: F.day(2026, 12, 1))
        #expect(repository.limitChanges == [F.day(2027, 2, 28), F.day(2027, 1, 31)])
        #expect(repository.snapshot.budgets.first?.limits.map(\.amount) == [7_000])
    }

    @Test("Delete removes the budget; reads that fail are passed on")
    func deleteAndFailures() throws {
        let budget = B.budget()
        let (repository, useCases) = try make([budget])
        try useCases.delete(budget.id)
        #expect(try useCases.budgets(today: today).isEmpty)
        repository.failsReads = true
        #expect(throws: FakeBudgetRepository.ReadFailure.self) { try useCases.budgets(today: today) }
    }
}
