import Foundation
import LittleOrbitDomain

/// The budget use cases the iOS Budgets screens need (#25), built once by the composition root.
public struct BudgetScreenUseCases {
    public let list: any ListBudgetsUseCase
    /// The New Budget and Edit Budget form's use cases. Without them the screen offers no way to make a budget.
    public let form: BudgetFormUseCases?

    public init(list: any ListBudgetsUseCase, form: BudgetFormUseCases? = nil) {
        self.list = list
        self.form = form
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

    /// Whether the screen offers New Budget: only when there's an unarchived expense category to pick, so the
    /// + button and “Create Budget” are hidden rather than shown disabled (UI Designer's #175 ruling 1).
    public func canCreateBudget() -> Bool {
        guard let categories = useCases.form?.categories, let listing = try? categories.listing() else {
            return false
        }
        return listing.categories.contains { $0.kind == .expense && !$0.isArchived }
    }

    /// The New Budget or Edit Budget form. Its save is recorded in `history`, the window's Undo history.
    /// Throws when the budgets or categories can't be read, or the budget being edited is gone.
    public func makeForm(
        _ mode: BudgetFormViewModel.Mode,
        history: @escaping @MainActor () -> WindowUndoHistory? = { nil },
    ) throws -> BudgetFormViewModel {
        guard let form = useCases.form else {
            throw BudgetFormUnavailable()
        }
        return try BudgetFormViewModel(
            mode: mode,
            useCases: form,
            today: today(),
            locale: locale,
            updates: updates,
            history: history,
        )
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

/// The screen was built without the form's use cases.
struct BudgetFormUnavailable: Error {}

/// The use cases the budget form needs (#25): the budget list for other budgets' names and the budget being
/// edited, saves that can be undone, and the category tree to pick from.
public struct BudgetFormUseCases {
    public let budgets: any ListBudgetsUseCase
    public let changes: any BudgetChangesUseCase
    public let categories: any LoadCategoriesUseCase

    public init(
        budgets: any ListBudgetsUseCase,
        changes: any BudgetChangesUseCase,
        categories: any LoadCategoriesUseCase,
    ) {
        self.budgets = budgets
        self.changes = changes
        self.categories = categories
    }
}
