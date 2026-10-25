import Foundation
import LittleOrbitDomain
import Observation

/// The iOS budget list (#25), pushed from the home screen's Budgets row. It reads the list use case only, and
/// the screen reloads it when the ledger changes (`BudgetsFeature.revision`).
@Observable
@MainActor
public final class BudgetsViewModel {
    /// Every budget, sorted by name, with its current period (or its first, before it starts).
    public private(set) var rows: [BudgetRow] = []
    /// A failed load. The list keeps what it last showed.
    public var alert: CategoryAlert?
    private var hasLoaded = false

    @ObservationIgnored private let list: any ListBudgetsUseCase
    @ObservationIgnored private let today: @MainActor () -> CalendarDay
    @ObservationIgnored private let money: MoneyFormatter
    @ObservationIgnored private let dates: BudgetStartDates

    public init(
        list: any ListBudgetsUseCase,
        today: @escaping @MainActor () -> CalendarDay,
        locale: Locale = .current,
    ) {
        self.list = list
        self.today = today
        money = MoneyFormatter(locale: locale)
        dates = BudgetStartDates(locale: locale)
    }

    public static var title: String { BudgetText.title }
    public static var emptyTitle: String { BudgetText.emptyTitle }
    public static var emptyMessage: String { BudgetText.emptyMessage }
    public static var footnote: String { BudgetText.footnote }

    /// The empty state shows once a load has found no budgets (S30), not before the first load.
    public var isEmpty: Bool {
        hasLoaded && rows.isEmpty
    }

    /// “5 budgets · 1 overspent”, under the Mac list's title. `nil` before the first load and with no budgets,
    /// when the empty state says it instead.
    public var summaryText: String? {
        guard hasLoaded, !rows.isEmpty else {
            return nil
        }
        let count = BudgetText.budgetCount(rows.count)
        let overspent = rows.filter { $0.status == .overspent }.count
        return overspent == 0 ? count : BudgetText.pair(count, BudgetText.overspentCount(overspent))
    }

    public func load() {
        do {
            let today = today()
            rows = try list.budgets(today: today).map { BudgetRow($0, today: today, money: money, dates: dates) }
            hasLoaded = true
        } catch {
            alert = BudgetText.loadFailed
        }
    }
}
