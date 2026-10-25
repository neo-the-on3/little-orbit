import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The iOS budget list (#25 part 2): each row's status, bar, amounts and timing, the empty state, a failed
/// load and the reload after a ledger change. Today is 20 Oct 2026.
@MainActor
@Suite("Budgets list (#25)")
struct BudgetsViewModelTests {
    typealias B = BudgetFeatureFixture  // swiftlint:disable:this type_name

    private func loaded(_ budgets: [Budget], _ transactions: [Transaction] = []) throws -> BudgetsViewModel {
        let model = B.feature(try B.repository(budgets, transactions)).makeList()
        model.load()
        return model
    }

    @Test("On track: what's left, spent of the limit, the repeat and the days left")
    func onTrack() throws {
        let model = try loaded([B.budget("Eating out", limit: 9_500)], [B.expense(3_450)])
        let row = try #require(model.rows.first)
        #expect(row.name == "Eating out")
        #expect(row.status == .onTrack)
        #expect(row.statusText == "₹6,050.00 left")
        #expect(row.statusSymbol == nil)
        #expect(row.amountsText == "₹3,450.00 of ₹9,500.00")
        #expect(row.timingText == "Monthly · 12 days left")
        #expect(abs(try #require(row.progress) - 3_450.0 / 9_500.0) < 0.000_1)
        // D308.6: the percentage is read after the amounts whenever more than 0 is available.
        #expect(
            row.accessibilityLabel == "Eating out, ₹6,050.00 left, ₹3,450.00 of ₹9,500.00, 36%, Monthly, 12 days left"
        )
    }

    @Test("S21: near the limit from 90%, with the share spent and a warning symbol")
    func nearLimit() throws {
        let model = try loaded([B.budget("Eating out", limit: 12_000)], [B.expense(11_250)])
        let row = try #require(model.rows.first)
        #expect(row.status == .nearLimit)
        #expect(row.statusText == "₹750.00 left")
        #expect(row.statusSymbol == "exclamationmark.triangle.fill")
        #expect(row.amountsText == "₹11,250.00 of ₹12,000.00 · 94%")
        #expect(
            row.accessibilityLabel
                == "Eating out, Near limit, ₹750.00 left, ₹11,250.00 of ₹12,000.00, 94%, Monthly, 12 days left"
        )
    }

    @Test("D308.5: while spent is below what's available the share is capped at 99%; 100% is exactly the limit")
    func percentCap() throws {
        let rows = try loaded(
            [
                B.budget("Eating out", limit: 1_000),
                B.budget("Shopping", limit: 1_000, categories: [B.shoppingID]),
            ],
            [B.expense(995), B.expense(1_000, in: B.shoppingID)],
        )
        .rows
        #expect(rows[0].status == .nearLimit)
        #expect(rows[0].amountsText == "₹995.00 of ₹1,000.00 · 99%")
        #expect(rows[0].accessibilityLabel.contains("₹995.00 of ₹1,000.00, 99%,"))
        #expect(rows[1].amountsText == "₹1,000.00 of ₹1,000.00 · 100%")
    }

    @Test("S22, S68: overspent shows the amount over, and the bar stops at full")
    func overspent() throws {
        let model = try loaded(
            [B.budget("Shopping", limit: 5_000, categories: [B.shoppingID])],
            [
                B.expense(6_200, in: B.shoppingID)
            ],
        )
        let row = try #require(model.rows.first)
        #expect(row.status == .overspent)
        #expect(row.statusText == "₹1,200.00 over")
        #expect(row.statusSymbol == "exclamationmark.circle")
        #expect(row.amountsText == "₹6,200.00 of ₹5,000.00")
        #expect(row.progress == 1)
        #expect(
            row.accessibilityLabel
                == "Shopping, Overspent, ₹1,200.00 over, ₹6,200.00 of ₹5,000.00, 124%, Monthly, 12 days left"
        )
    }

    @Test("Exactly at the limit is near the limit, not overspent (S22)")
    func atLimit() throws {
        let model = try loaded([B.budget("Eating out", limit: 5_000)], [B.expense(5_000)])
        let row = try #require(model.rows.first)
        #expect(row.status == .nearLimit)
        #expect(row.statusText == "₹0.00 left")
        #expect(row.progress == 1)
    }

    @Test("D307.2: at exactly 0 available with nothing spent, it's nothing spent yet, not overspent")
    func zeroAvailable() throws {
        let budget = B.budget(
            "Eating out",
            limit: 1_000,
            from: CalendarDay(year: 2026, month: 9, day: 1),
            carriesOverOverspending: true,
        )
        let row = try #require(try loaded([budget], [B.expense(2_000, month: 9)]).rows.first)
        #expect(row.status == .nothingSpent)
        #expect(row.statusText == "Nothing spent yet")
        #expect(row.amountsText == "₹0.00 of ₹0.00")
        #expect(row.progress == 0)
    }

    @Test("D307.2 and its amendment: below 0 available it's overspent from the first day, naming spent and available")
    func negativeAvailable() throws {
        let budget = B.budget(
            "Eating out",
            limit: 1_000,
            from: CalendarDay(year: 2026, month: 9, day: 1),
            carriesOverOverspending: true,
        )
        let row = try #require(try loaded([budget], [B.expense(2_500, month: 9)]).rows.first)
        #expect(row.status == .overspent)
        #expect(row.statusText == "₹500.00 over")
        #expect(row.amountsText == "₹0.00 spent · −₹500.00 available")
        #expect(row.progress == 1)
        // No percentage: nothing is available.
        #expect(
            row.accessibilityLabel
                == "Eating out, Overspent, ₹500.00 over, ₹0.00 spent, −₹500.00 available, Monthly, 12 days left"
        )

        let spending = try #require(
            try loaded([budget], [B.expense(2_500, month: 9), B.expense(300)]).rows.first
        )
        #expect(spending.statusText == "₹800.00 over")
        #expect(spending.amountsText == "₹300.00 spent · −₹500.00 available")
    }

    @Test("Nothing spent yet, on a weekly budget")
    func nothingSpent() throws {
        let weekly = B.budget(
            "Travel",
            limit: 2_000,
            categories: [B.shoppingID],
            from: CalendarDay(year: 2026, month: 10, day: 15),
            recurrence: .weekly,
        )
        let row = try #require(try loaded([weekly]).rows.first)
        #expect(row.status == .nothingSpent)
        #expect(row.statusText == "Nothing spent yet")
        #expect(row.progress == 0)
        #expect(row.amountsText == "₹0.00 of ₹2,000.00")
        #expect(row.timingText == "Weekly · 2 days left")
    }

    @Test("D308 amendment: before the start date, one secondary status with the date, no bar, and only the repeat")
    func notStarted() throws {
        let yearly = B.budget(
            "Holidays",
            limit: 50_000,
            from: CalendarDay(year: 2026, month: 11, day: 1),
            recurrence: .yearly,
        )
        let tomorrow = B.budget(
            "Gifts",
            limit: 1_000,
            from: CalendarDay(year: 2026, month: 10, day: 21),
            recurrence: .fortnightly,
        )
        let nextYear = B.budget(
            "Pilgrimage",
            limit: 20_000,
            from: CalendarDay(year: 2027, month: 1, day: 3),
            recurrence: .monthly,
        )
        let rows = try loaded([yearly, tomorrow, nextYear]).rows
        #expect(rows.map(\.name) == ["Gifts", "Holidays", "Pilgrimage"])
        #expect(rows.map(\.status) == [.notStarted, .notStarted, .notStarted])
        // The day before, then the date without the year in the current year, and with it in another.
        #expect(rows.map(\.statusText) == ["Starts tomorrow", "Starts 1 Nov", "Starts 3 Jan 2027"])
        #expect(rows.map(\.statusSymbol) == [nil, nil, nil])
        #expect(rows.map(\.progress) == [nil, nil, nil])
        #expect(rows.map(\.timingText) == ["Fortnightly", "Yearly", "Monthly"])
        #expect(rows[1].amountsText == "₹0.00 of ₹50,000.00")
        #expect(rows[1].accessibilityLabel == "Holidays, Starts 1 Nov, ₹0.00 of ₹50,000.00, Yearly")
        #expect(rows[0].accessibilityLabel == "Gifts, Starts tomorrow, ₹0.00 of ₹1,000.00, Fortnightly")
    }

    @Test("D308.3: on a period's last day the timing reads “Last day”")
    func lastDay() throws {
        let weekly = B.budget(
            "Travel",
            limit: 2_000,
            categories: [B.shoppingID],
            from: CalendarDay(year: 2026, month: 10, day: 14),
            recurrence: .weekly,
        )
        let row = try #require(try loaded([weekly]).rows.first)
        #expect(row.timingText == "Weekly · Last day")
        #expect(row.accessibilityLabel.hasSuffix(", Weekly, Last day"))
    }

    @Test("D308 amendment 2: a budget with no categories shows only its name and “No categories”")
    func noCategories() throws {
        let repository = try B.repository([
            B.budget("Monthly food", limit: 8_000),
            B.budget("Shopping", limit: 500, categories: [B.shoppingID]),
        ])
        try repository.deleteCategory(id: B.eatingOutID, reassigningTo: nil)
        let model = B.feature(repository).makeList()
        model.load()
        let row = try #require(model.rows.first)
        #expect(row.name == "Monthly food")
        #expect(row.status == .noCategories)
        #expect(row.statusText == "No categories")
        #expect(row.statusSymbol == nil)
        #expect(row.progress == nil)
        #expect(row.amountsText == nil)
        #expect(row.timingText == nil)
        #expect(row.accessibilityLabel == "Monthly food, No categories")
        #expect(model.rows[1].status == .nothingSpent)
    }

    @Test("Custom repeats read as every so many days, weeks, months or years")
    func customRepeats() throws {
        let rows = try loaded([
            B.budget("A", limit: 100, recurrence: .custom(every: 1, unit: .day)),
            B.budget("B", limit: 100, recurrence: .custom(every: 3, unit: .week)),
            B.budget("C", limit: 100, recurrence: .custom(every: 2, unit: .month)),
            B.budget("D", limit: 100, recurrence: .custom(every: 5, unit: .year)),
        ])
        .rows
        #expect(
            rows.map { $0.timingText?.components(separatedBy: " · ").first } == [
                "Every day", "Every 3 weeks", "Every 2 months", "Every 5 years",
            ]
        )
        #expect(rows[0].timingText == "Every day · Last day")
    }

    @Test("Rows keep the list's order, by name")
    func sortedByName() throws {
        let rows = try loaded([
            B.budget("groceries", limit: 100),
            B.budget("Eating out", limit: 100),
            B.budget("Travel", limit: 100),
        ])
        .rows
        #expect(rows.map(\.name) == ["Eating out", "groceries", "Travel"])
    }

    @Test("S30: the empty state shows once the list has loaded with no budgets")
    func empty() throws {
        let model = B.feature(try B.repository()).makeList()
        #expect(!model.isEmpty)
        model.load()
        #expect(model.rows.isEmpty)
        #expect(model.isEmpty)
        #expect(model.alert == nil)
        #expect(BudgetsViewModel.emptyTitle == "No budgets yet")
        #expect(
            BudgetsViewModel.emptyMessage
                == "Set a spending limit for a group of expense categories, like Eating out or Groceries. It resets every week, fortnight, month or year."
        )
    }

    @Test("A list that can't be read shows an alert, not the empty state")
    func loadFailure() {
        let model = BudgetsFeature(
            useCases: BudgetScreenUseCases(list: UnreadableBudgets()),
            today: { TransactionFeatureFixture.today },
        )
        .makeList()
        model.load()
        #expect(model.alert?.title == "Couldn’t Load Budgets")
        #expect(model.alert?.message == "Try again.")
        #expect(!model.isEmpty)
    }

    @Test(
        "D308.8: the footnote explains what counts as spent, every refund included, and when a budget is near its limit"
    )
    func footnote() {
        #expect(
            BudgetsViewModel.footnote
                == "Spent = expenses in the budget’s categories and subcategories, minus refunds. Transfers never count. Near limit is 90% or more."
        )
    }

    @Test("#25 AC 6: a ledger change bumps the revision, and the reload shows it")
    func liveUpdates() throws {
        let repository = try B.repository([B.budget("Eating out", limit: 9_500)])
        let updates = LedgerUpdates()
        let feature = B.feature(repository, updates: updates)
        let model = feature.makeList()
        model.load()
        #expect(model.rows.first?.statusText == "Nothing spent yet")
        let before = feature.revision
        try repository.saveTransaction(B.expense(3_450))
        updates.ledgerReplaced()
        #expect(feature.revision == before + 1)
        model.load()
        #expect(model.rows.first?.statusText == "₹6,050.00 left")
    }

    @Test("A feature with no updates source stays at revision 0")
    func noUpdates() throws {
        #expect(B.feature(try B.repository()).revision == 0)
    }
}
