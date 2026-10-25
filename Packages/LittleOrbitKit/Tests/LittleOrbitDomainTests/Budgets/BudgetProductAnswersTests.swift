import Foundation
import LittleOrbitDomain
import Testing

/// Product Manager's D307 answers that belong in Domain (#174): overspent at 0 or less available, the currency
/// hint with no account in the budget's currency, a budget with no categories left, and unique names.
@Suite("Budget answers D307 (#25)")
struct BudgetProductAnswersTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias B = BudgetFixture  // swiftlint:disable:this type_name

    private let today = F.day(2026, 11, 20)
    private let now = F.date(2026, 11, 5)

    /// A budget from 1 Oct carrying overspending, with `octoberSpent` in October and nothing in November.
    private func november(afterSpending octoberSpent: Decimal) throws -> BudgetPeriodFigures {
        let budget = B.budget(from: F.day(2026, 10, 1), overspending: true)
        let snapshot = try B.saving([B.expense(octoberSpent, on: F.date(2026, 10, 10))], budgets: [budget])
        return BudgetProgress.summary(of: budget, today: today, in: snapshot).current
    }

    @Test("D307.2: below 0 available with nothing spent is overspent from the first day")
    func belowZeroIsOverspent() throws {
        let figures = try november(afterSpending: 17_000)
        #expect(figures.figures.available == -1_000)
        #expect(figures.figures.spent == 0)
        #expect(figures.state == .overspent)
    }

    @Test("D307.2: exactly 0 available with nothing spent isn't overspent or near the limit")
    func exactlyZeroIsNotOverspent() throws {
        let figures = try november(afterSpending: 16_000)
        #expect(figures.figures.available == 0)
        #expect(figures.state == .onTrack)
    }

    @Test("D307.3: the hint shows with no account in the budget's currency, and not otherwise")
    func noAccountInCurrency() throws {
        let euro = B.budget("Abroad", currency: "EUR")
        let snapshot = try B.saving([], budgets: [euro, B.budget()])
        let hint = BudgetProgress.summary(of: euro, today: today, in: snapshot).current
        #expect(hint.hasNoAccountInCurrency)
        #expect(hint.showsCurrencyHint)
        let rupees = BudgetProgress.summary(of: B.budget(), today: today, in: snapshot).current
        #expect(!rupees.hasNoAccountInCurrency)
        #expect(!rupees.showsCurrencyHint)
    }

    @Test("D307.5: a budget left with no categories is kept, and an overspent one isn't counted in the badge")
    func noCategoriesLeft() throws {
        let budget = B.budget(categories: [B.travelID], from: F.day(2026, 10, 1), overspending: true)
        var snapshot = try B.saving(
            [B.expense(17_000, in: B.travelID, on: F.date(2026, 10, 10))],
            budgets: [budget],
        )
        #expect(BudgetProgress.summary(of: budget, today: today, in: snapshot).isOverspent)
        snapshot = try LedgerBook.deletingCategory(id: B.travelID, reassigningTo: nil, in: snapshot, now: now)
        let kept = try #require(snapshot.budgets.first)
        #expect(kept.categoryIDs.isEmpty)
        let summary = BudgetProgress.summary(of: kept, today: today, in: snapshot)
        #expect(summary.hasNoCategories)
        #expect(!summary.isOverspent)
    }

    @Test("D307.5: the badge use case skips a budget with no categories left")
    @MainActor
    func badgeSkipsNoCategories() throws {
        let empty = B.budget("Trips", categories: [B.travelID], from: F.day(2026, 10, 1), overspending: true)
        let over = B.budget("Eating out", from: F.day(2026, 10, 1), overspending: true)
        var snapshot = try B.saving(
            [
                B.expense(17_000, in: B.travelID, on: F.date(2026, 10, 10)),
                B.expense(17_000, on: F.date(2026, 10, 10)),
            ],
            budgets: [empty, over],
        )
        snapshot = try LedgerBook.deletingCategory(id: B.travelID, reassigningTo: nil, in: snapshot, now: now)
        let useCases = DefaultBudgetUseCases(repository: FakeBudgetRepository(snapshot), now: { now })
        #expect(try useCases.budgets(today: today).count == 2)
        #expect(try useCases.overspentCount(today: today) == 1)
    }

    @Test("D307.6: a name another budget has, trimmed and ignoring case, is refused; the same budget can keep it")
    func uniqueNames() throws {
        let first = B.budget("Eating out")
        let snapshot = try B.saving([], budgets: [first])
        #expect(throws: LedgerValidationError.duplicateBudgetName) {
            try LedgerBook.savingBudget(B.budget("  eating OUT "), in: snapshot, now: now)
        }
        var renamed = first
        renamed.name = "EATING OUT"
        #expect(try LedgerBook.savingBudget(renamed, in: snapshot, now: now).budgets.first?.name == "EATING OUT")
        let deleted = try LedgerBook.deletingBudget(id: first.id, in: snapshot)
        #expect(try LedgerBook.savingBudget(B.budget("Eating out"), in: deleted, now: now).budgets.count == 1)
    }

    @Test("D307.8: saving a deleted budget again brings back the same ID and limit history")
    func undoDelete() throws {
        var budget = B.budget()
        budget.limits.append(BudgetLimit(startDay: F.day(2026, 12, 1), amount: 9_000, createdAt: now))
        let snapshot = try B.saving([], budgets: [budget])
        let saved = try #require(snapshot.budgets.first)
        let deleted = try LedgerBook.deletingBudget(id: budget.id, in: snapshot)
        let restored = try #require(try LedgerBook.savingBudget(saved, in: deleted, now: now).budgets.first)
        #expect(restored == saved)
    }
}
