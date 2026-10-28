import Foundation
import LittleOrbitDomain

/// Counts for the iOS home section and the macOS sidebar rows.
///
/// Budgets (#25) and Scheduled (#26) aren't built yet. Until they are, `NoPlannedItems` reports none, so the rows
/// show "No budgets yet" and "Nothing scheduled" with no badge (D104).
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
    /// The accounts a scheduled item uses, as its account or as To, Completed items included: Edit Account locks
    /// their currency (D381.3). Throws when the items can't be read, so Edit Account can fail closed.
    func scheduledAccountIDs() throws -> Set<UUID>
    /// The scheduled items an account delete deletes with it, for its confirmation (D288). Throws when the items
    /// can't be read, so the confirmation fails closed rather than leaving them out (n5, Tech Architect 5681779824).
    func scheduledItems() throws -> [ScheduledItem]
}

extension PlannedItemsSource {
    /// None, for a source with no scheduled items.
    public func scheduledAccountIDs() -> Set<UUID> { [] }
    /// None, for a source with no scheduled items.
    public func scheduledItems() -> [ScheduledItem] { [] }
}

/// Used until #25 and #26 provide real counts.
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
