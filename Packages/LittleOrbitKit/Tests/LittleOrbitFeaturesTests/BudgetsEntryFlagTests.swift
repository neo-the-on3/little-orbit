import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// D423 (#308): Budgets ships only with the #25 stack. With the flag off there's no Budgets row on the Mac sidebar
/// or the iPhone and iPad Accounts home, which both list `homeRows`; Scheduled and Reports keep their D58 order and
/// badges. Made-up data only.
@MainActor
@Suite("Budgets entry flag (D423)")
struct BudgetsEntryFlagTests {
    private let counts = PlannedItemCounts(
        budgetCount: 1,
        overspentBudgetCount: 1,
        scheduledItemCount: 1,
        overdueOccurrenceCount: 1,
    )

    private func model(budgetsEnabled: Bool? = nil) throws -> AccountsViewModel {
        let repository = try FeatureFixture.repository([
            Account(name: "Everyday Checking", type: .checking, currencyCode: "USD", openingBalance: 1_250)
        ])
        let model =
            if let budgetsEnabled {
                AccountsViewModel(
                    useCases: FeatureFixture.useCases(repository),
                    plannedItems: StubPlannedItems(counts),
                    budgetsEnabled: budgetsEnabled,
                    locale: Locale(identifier: "en_US"),
                )
            } else {
                AccountsViewModel(
                    useCases: FeatureFixture.useCases(repository),
                    plannedItems: StubPlannedItems(counts),
                    locale: Locale(identifier: "en_US"),
                )
            }
        model.load()
        return model
    }

    @Test("The 1.0 build has the flag off")
    func offInOnePointZero() {
        #expect(FeatureFlags.budgetsEnabled == false)
    }

    @Test("Checks 1, 2 and 5: flag off, only Scheduled and Reports, Scheduled keeps its badge, no No budgets yet")
    func flagOff() throws {
        let model = try model()
        #expect(model.homeRows.map(\.destination) == [.scheduled, .reports])
        #expect(model.homeRows.map(\.title) == ["Scheduled", "Reports"])
        #expect(model.homeRows.first?.badge == "1")
        #expect(model.homeRows.first?.accessibilityLabel == "Scheduled, 1 overdue")
        #expect(!model.homeRows.contains { $0.subtitle == "No budgets yet" })
        #expect(!model.homeRows.contains { $0.accessibilityLabel.contains("Budgets") })
    }

    @Test("Before the first load the rows are the same: no Budgets row ever shows with the flag off")
    func flagOffBeforeLoad() throws {
        let model = AccountsViewModel(
            useCases: FeatureFixture.useCases(try FeatureFixture.repository([])),
            budgetsEnabled: false,
        )
        #expect(model.homeRows.map(\.destination) == [.scheduled, .reports])
    }

    @Test("Check 4: flag on, Budgets is back first in its D58 place with its badge")
    func flagOn() throws {
        let model = try model(budgetsEnabled: true)
        #expect(model.homeRows.map(\.destination) == [.budgets, .scheduled, .reports])
        #expect(model.homeRows.map(\.badge) == ["1", "1", nil])
        #expect(model.homeRows.first?.accessibilityLabel == "Budgets, 1 overspent")
    }
}
