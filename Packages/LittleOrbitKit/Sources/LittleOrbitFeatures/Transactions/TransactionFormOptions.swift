import Foundation
import LittleOrbitDomain

/// The choices the entry sheet and bulk edit offer.
public struct TransactionAccountOption: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var currencyCode: String
    /// "Everyday Savings · INR", as on the transfer From and To rows.
    public var label: String { "\(name) · \(currencyCode)" }
}

public struct TransactionCategoryOption: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var symbolName: String
    public var isSubcategory: Bool
    /// The parent category, for grouping (`TransactionCategoryGroup`).
    public var parentID: UUID?
}

/// One parent category with its subcategories under it: a section in the category picker, so the hierarchy
/// shows with standard grouping and every item is a plain `Label` that lines up (UI Designer, #87).
public struct TransactionCategoryGroup: Identifiable, Equatable, Sendable {
    public var parent: TransactionCategoryOption
    public var subcategories: [TransactionCategoryOption]
    public var id: UUID { parent.id }

    /// Groups options in their order: each top-level category with the subcategories whose parent it is. A
    /// subcategory whose parent isn't offered (archived, or another kind) stands as its own group.
    public static func groups(_ options: [TransactionCategoryOption]) -> [TransactionCategoryGroup] {
        let offered = Set(options.map(\.id))
        let tops = options.filter { option in option.parentID.map { !offered.contains($0) } ?? true }
        return tops.map { top in
            TransactionCategoryGroup(parent: top, subcategories: options.filter { $0.parentID == top.id })
        }
    }
}

extension TransactionCategoryGroup {
    /// What VoiceOver reads as the category picker's value: "Groceries", or "Groceries, under Food" for a
    /// subcategory, so its parent is heard too; "Uncategorised" for none (Tester's #87 blocker). The picker
    /// shows only the name, as text, so the value is never read from the icon's element.
    public static func spokenValue(of id: UUID?, in categories: [TransactionCategory]) -> String {
        guard let category = categories.first(where: { $0.id == id }) else {
            return TransactionText.uncategorised
        }
        guard let parent = categories.first(where: { $0.id == category.parentID }) else {
            return category.name
        }
        return FeatureText.format("%1$@, under %2$@", category.name, parent.name)
    }
}
