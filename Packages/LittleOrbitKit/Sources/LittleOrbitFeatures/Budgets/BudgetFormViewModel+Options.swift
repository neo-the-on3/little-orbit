import Foundation
import LittleOrbitDomain

/// One row of the budget form's Categories screen (#25 design: Categories – multi-select).
public struct BudgetCategoryOption: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let symbolName: String
    public let hue: CategoryHue
    public let isSubcategory: Bool
    /// “3 subcategories” under a parent that has any.
    public let subtitle: String?
}

/// One of the next periods the Repeat screen lists: “1–21 Oct 2026”, the first marked “This period”.
public struct BudgetPeriodPreview: Identifiable, Equatable, Sendable {
    public let id: Int
    public let dates: String
    public let isCurrent: Bool
}

extension BudgetFormViewModel {
    // MARK: Categories

    /// Unarchived expense categories, each parent followed by its subcategories, in the tree's order. Archived
    /// ones show only while picked. Income and transfers never count towards a budget, so they aren't listed.
    public var categoryOptions: [BudgetCategoryOption] {
        let expense = listing.categories.filter { $0.kind == .expense && (!$0.isArchived || isPicked($0.id)) }
        return expense.filter { $0.parentID == nil }
            .flatMap { parent in
                let children = expense.filter { $0.parentID == parent.id }
                return [option(parent, subcategoryCount: children.count)]
                    + children.map { option($0, subcategoryCount: 0) }
            }
    }

    /// Whether the form can make a budget: there's at least one unarchived expense category to pick.
    public var hasCategoriesToPick: Bool {
        listing.categories.contains { $0.kind == .expense && !$0.isArchived }
    }

    /// A category shows ticked when it's picked or its parent is.
    public func isSelected(_ id: UUID) -> Bool {
        categoryIDs.contains(id) || isIncludedByParent(id)
    }

    /// A subcategory whose parent is picked is included already, so it can't be picked on its own.
    public func isIncludedByParent(_ id: UUID) -> Bool {
        guard let parentID = listing.category(id)?.parentID else {
            return false
        }
        return categoryIDs.contains(parentID)
    }

    /// Picks or unpicks a category. Picking a parent drops its subcategories, which it includes.
    public func toggleCategory(_ id: UUID) {
        guard !isIncludedByParent(id) else {
            return
        }
        if categoryIDs.contains(id) {
            categoryIDs.remove(id)
        } else {
            let children = Set(listing.subcategories(of: id).map(\.id))
            categoryIDs = categoryIDs.subtracting(children).union([id])
        }
    }

    /// “Expense categories · 2 selected”, the Categories screen's section header.
    public var categoriesHeader: String {
        BudgetText.categoriesHeader(categoryIDs.count)
    }

    /// The Categories row's value: “Restaurants, Coffee”, or “None”.
    public var categoriesSummary: String {
        let names = orderedCategoryIDs.compactMap { listing.category($0)?.name }
        return names.isEmpty ? BudgetText.none : BudgetText.shortList(names)
    }

    /// The picked categories in the tree's order, as the budget stores them.
    var orderedCategoryIDs: [UUID] {
        listing.categories.map(\.id).filter(categoryIDs.contains)
    }

    func reloadCategories() {
        guard let fresh = try? useCases.categories.listing() else {
            return
        }
        listing = fresh
        let live = Set(fresh.categories.filter { $0.kind == .expense }.map(\.id))
        categoryIDs = categoryIDs.intersection(live)
    }

    private func isPicked(_ id: UUID) -> Bool {
        categoryIDs.contains(id)
    }

    private func option(_ category: TransactionCategory, subcategoryCount: Int) -> BudgetCategoryOption {
        let parent = category.parentID.flatMap(listing.category)
        return BudgetCategoryOption(
            id: category.id,
            name: category.name,
            symbolName: CategoryAppearance.symbol(of: category),
            hue: CategoryAppearance.hue(of: parent ?? category),
            isSubcategory: category.parentID != nil,
            subtitle: subcategoryCount > 0 ? BudgetText.subcategoryCount(subcategoryCount) : nil,
        )
    }

    // MARK: Currency

    /// Circulating currencies, plus the budget's own code if it was stored with another one.
    public var currencyOptions: [String] {
        let codes = CurrencyCode.circulatingCodes
        return codes.contains(currencyCode) ? codes : (codes + [currencyCode]).sorted()
    }

    /// “INR — Indian Rupee”.
    public func currencyTitle(for code: String) -> String {
        BudgetText.currencyTitle(code, name: locale.localizedString(forCurrencyCode: code) ?? code)
    }

    // MARK: Repeat

    public func repeatTitle(_ choice: RepeatChoice) -> String {
        switch choice {
        case .weekly: BudgetText.recurrence(.weekly)
        case .fortnightly: BudgetText.recurrence(.fortnightly)
        case .monthly: BudgetText.recurrence(.monthly)
        case .yearly: BudgetText.recurrence(.yearly)
        case .custom: BudgetText.custom
        }
    }

    /// The Repeat row's value: “Monthly”, or “Every 3 weeks”.
    public var repeatSummary: String {
        BudgetText.recurrence(recurrence)
    }

    /// “Week” or “Weeks”, to read with the stepper's “Every 1” or “Every 3” (D309.5).
    public func unitTitle(_ unit: BudgetRecurrenceUnit) -> String {
        BudgetText.unit(unit, count: customCount)
    }

    /// The Period section's footnote. The month example only matters when periods are months or years.
    public var periodFootnote: String {
        switch recurrence.step.unit {
        case .day, .week: BudgetText.periodFootnote
        case .month, .year: CategoryText.sentences([BudgetText.periodFootnote, BudgetText.monthEndFootnote])
        }
    }

    /// The current period (or the first, before the start day) and the two after it.
    public var nextPeriods: [BudgetPeriodPreview] {
        guard recurrence.isValid else {
            return []
        }
        let schedule = BudgetSchedule(startDay: startDay, recurrence: recurrence)
        let first = schedule.currentOrFirstPeriod(today: today).index
        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        formatter.calendar = BudgetDays.calendar
        formatter.timeZone = BudgetDays.calendar.timeZone
        formatter.dateTemplate = "dMMMy"
        return (first..<first + 3)
            .map { index in
                let period = schedule.period(index)
                return BudgetPeriodPreview(
                    id: index,
                    dates: formatter.string(from: BudgetDays.date(period.start), to: BudgetDays.date(period.end)),
                    isCurrent: period.contains(today),
                )
            }
    }
}
