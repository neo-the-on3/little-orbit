import Foundation
import LittleOrbitDomain

/// The budget use cases the iOS Budgets screens need (#25), built once by the composition root.
public struct BudgetScreenUseCases {
    public let list: any ListBudgetsUseCase

    public init(list: any ListBudgetsUseCase) {
        self.list = list
    }
}

/// Everything the Budgets screens need (#25), built once by the composition root from the injected use
/// cases. "Today" is the device's calendar day.
@MainActor
public final class BudgetsFeature {
    public let useCases: BudgetScreenUseCases
    private let updates: LedgerUpdates?
    private let today: @MainActor () -> CalendarDay
    private let locale: Locale

    /// `updates` is the ledger's change counter, so the list reloads after any change, as the other screens
    /// do (#25 AC 6).
    public init(
        useCases: BudgetScreenUseCases,
        updates: LedgerUpdates? = nil,
        locale: Locale = .current,
        today: @escaping @MainActor () -> CalendarDay = { TransactionTiming.today(Date()) },
    ) {
        self.useCases = useCases
        self.updates = updates
        self.locale = locale
        self.today = today
    }

    /// Changes after every ledger change; the screens reload when it does.
    public var revision: Int {
        updates?.revision ?? 0
    }

    public func makeList() -> BudgetsViewModel {
        BudgetsViewModel(list: useCases.list, today: today, locale: locale)
    }

    /// The budget counts for the home screen's Budgets row and its overspent badge (#25 AC 5).
    public var plannedItems: any PlannedItemsSource {
        BudgetPlannedItems(list: useCases.list, today: today)
    }
}

/// The home section's budget counts from the list use case. Scheduled (#26) isn't built yet, so it reports
/// none. Budgets that can't be read count as none, so the home screen still loads.
@MainActor
final class BudgetPlannedItems: PlannedItemsSource {
    private let list: any ListBudgetsUseCase
    private let today: @MainActor () -> CalendarDay

    init(list: any ListBudgetsUseCase, today: @escaping @MainActor () -> CalendarDay) {
        self.list = list
        self.today = today
    }

    func plannedItemCounts() -> PlannedItemCounts {
        guard let budgets = try? list.budgets(today: today()) else {
            return PlannedItemCounts()
        }
        return PlannedItemCounts(
            budgetCount: budgets.count,
            overspentBudgetCount: budgets.filter(\.isOverspent).count,
        )
    }
}
