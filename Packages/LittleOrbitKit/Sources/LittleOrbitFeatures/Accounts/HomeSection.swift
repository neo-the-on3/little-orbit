import Foundation

/// Counts for the iOS home section and the macOS sidebar rows.
///
/// The App counts budgets with `BudgetsFeature.plannedItems` (#25). Scheduled (#26) isn't built yet, so it reports
/// none, and the row shows "Nothing scheduled" with no badge (D104). `NoPlannedItems` reports none of either.
public struct PlannedItemCounts: Equatable, Sendable {
    public var budgetCount: Int
    /// Overspent budgets. Exactly at the limit doesn't count (#25).
    public var overspentBudgetCount: Int
    public var scheduledItemCount: Int
    /// Overdue occurrences, not items (D106).
    public var overdueOccurrenceCount: Int

    public init(
        budgetCount: Int = 0,
        overspentBudgetCount: Int = 0,
        scheduledItemCount: Int = 0,
        overdueOccurrenceCount: Int = 0,
    ) {
        self.budgetCount = budgetCount
        self.overspentBudgetCount = overspentBudgetCount
        self.scheduledItemCount = scheduledItemCount
        self.overdueOccurrenceCount = overdueOccurrenceCount
    }
}

@MainActor
public protocol PlannedItemsSource: AnyObject {
    func plannedItemCounts() -> PlannedItemCounts
}

/// No budgets and nothing scheduled: for previews and tests, and the default before the App injects real counts.
@MainActor
public final class NoPlannedItems: PlannedItemsSource {
    public init() {}

    public func plannedItemCounts() -> PlannedItemCounts {
        PlannedItemCounts()
    }
}

public enum HomeDestination: String, CaseIterable, Identifiable, Sendable {
    case budgets
    case scheduled
    case reports

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .budgets: "Budgets"
        case .scheduled: "Scheduled"
        case .reports: "Reports"
        }
    }

    public var symbolName: String {
        switch self {
        case .budgets: "chart.line.uptrend.xyaxis"
        case .scheduled: "clock"
        case .reports: "doc.text.fill"
        }
    }

    /// The empty state: an iOS row subtitle, and the macOS detail pane when the row is picked (S85).
    public var emptyText: String {
        switch self {
        case .budgets: "No budgets yet"
        case .scheduled: "Nothing scheduled"
        case .reports: "No transactions yet"
        }
    }
}

/// One row of the home section (D54, D104).
public struct HomeRowModel: Identifiable, Equatable, Sendable {
    public var destination: HomeDestination
    /// iOS only. macOS sidebar rows stay one line (S85, S93).
    public var subtitle: String?
    public var badge: String?
    public var accessibilityLabel: String

    public var id: HomeDestination { destination }
    public var title: String { destination.title }
    public var symbolName: String { destination.symbolName }

    static func rows(counts: PlannedItemCounts, hasAnyTransaction: Bool) -> [HomeRowModel] {
        [
            make(.budgets, isEmpty: counts.budgetCount == 0, count: counts.overspentBudgetCount, noun: "overspent"),
            make(
                .scheduled,
                isEmpty: counts.scheduledItemCount == 0,
                count: counts.overdueOccurrenceCount,
                noun: "overdue",
            ),
            make(.reports, isEmpty: !hasAnyTransaction, count: 0, noun: ""),
        ]
    }

    private static func make(_ destination: HomeDestination, isEmpty: Bool, count: Int, noun: String) -> HomeRowModel {
        let subtitle = isEmpty ? destination.emptyText : nil
        let badge = CountBadge.text(for: count)
        var spoken = [destination.title]
        if let subtitle {
            spoken.append(subtitle)
        } else if badge != nil {
            spoken.append("\(count) \(noun)")
        }
        return HomeRowModel(
            destination: destination,
            subtitle: subtitle,
            badge: badge,
            accessibilityLabel: spoken.joined(separator: ", "),
        )
    }
}
