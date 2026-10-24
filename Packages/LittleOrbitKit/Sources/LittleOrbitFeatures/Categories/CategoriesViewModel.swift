import Foundation
import LittleOrbitDomain
import Observation

/// One row of the category tree, the Archived section or a target list.
public struct CategoryRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    /// "Expense · 25 transactions", or "Expense · 2 subcategories" for a parent with subcategories.
    public let subtitle: String
    public let symbolName: String
    public let hue: CategoryHue
    public let isSubcategory: Bool
}

/// A top-level category with its subcategories.
public struct CategoryRowGroup: Identifiable, Equatable, Sendable {
    public let parent: CategoryRow
    public let subcategories: [CategoryRow]
    public var id: UUID { parent.id }
}

/// An alert with an OK button.
public struct CategoryAlert: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let title: String
    public let message: String

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message
    }
}

/// The delete alert for one category (D19, D287.3). A category nothing uses gets the simple confirmation.
public struct CategoryDeletePrompt: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let message: String
    public let isUnused: Bool
}

/// iOS Settings › Categories (#24): the Expense and Income trees, reorder, Archived with Unarchive, and the
/// delete, move and merge choices. It depends only on use-case protocols. Merge and delete aren't Undo steps;
/// after one, `onRemoval` clears this window's Undo and Redo history (D287.2, D287.4).
@MainActor
@Observable
public final class CategoriesViewModel {
    public var kind: CategoryKind = .expense
    public private(set) var listing = CategoryListing(categories: [], usage: [:])
    /// A failed change, or a refused merge (D291.1).
    public var alert: CategoryAlert?
    public var deletePrompt: CategoryDeletePrompt?
    /// The editor sheet on show. Opening one sets it straight away from the loaded tree, with nothing
    /// to wait for, so a tap on a row presents its sheet at once.
    public var editor: CategoryEditorViewModel?
    /// Clears this window's Undo and Redo history; the screen sets it (D287.4).
    @ObservationIgnored public var onRemoval: () -> Void = {}

    @ObservationIgnored private let useCases: CategoryScreenUseCases
    @ObservationIgnored private let changed: () -> Void

    public init(useCases: CategoryScreenUseCases, changed: @escaping () -> Void = {}) {
        self.useCases = useCases
        self.changed = changed
    }

    // MARK: Reading

    public func load() {
        do {
            // The built-in categories were seeded once at launch (D291.7); this only reads.
            listing = try useCases.load.listing()
        } catch {
            alert = CategoryAlert(title: CategoryText.couldntSaveTitle, message: CategoryText.nothingChanged)
        }
    }

    /// The live, unarchived top-level categories of the chosen kind, with their unarchived subcategories.
    public var groups: [CategoryRowGroup] {
        topLevel(kind)
            .map { parent in
                CategoryRowGroup(
                    parent: row(parent),
                    subcategories: liveSubcategories(of: parent.id).map(row),
                )
            }
    }

    /// Archived categories of the chosen kind: archived top-level ones, and archived subcategories of live
    /// parents. A subcategory of an archived parent comes back with it.
    public var archivedRows: [CategoryRow] {
        listing.categories
            .filter { category in
                guard category.kind == kind, category.isArchived else {
                    return false
                }
                guard let parentID = category.parentID else {
                    return true
                }
                return listing.category(parentID)?.isArchived == false
            }
            .map(row)
    }

    public func category(_ id: UUID) -> TransactionCategory? {
        listing.category(id)
    }

    /// A subcategory always shows its parent's colour, whatever it has stored (UI Designer's #155 ruling).
    func hue(of category: TransactionCategory) -> CategoryHue {
        CategoryAppearance.hue(of: category.parentID.flatMap(listing.category) ?? category)
    }

    func row(_ category: TransactionCategory) -> CategoryRow {
        let subcategoryCount = category.parentID == nil ? liveSubcategories(of: category.id).count : 0
        return CategoryRow(
            id: category.id,
            name: category.name,
            subtitle: subcategoryCount > 0 && !category.isArchived
                ? CategoryText.parentSummary(
                    kind: category.kind,
                    count: listing.uses(of: category.id),
                    subcategoryCount: subcategoryCount,
                )
                : CategoryText.usage(kind: category.kind, count: listing.uses(of: category.id)),
            symbolName: CategoryAppearance.symbol(of: category),
            hue: hue(of: category),
            isSubcategory: category.parentID != nil,
        )
    }

    private func topLevel(_ kind: CategoryKind) -> [TransactionCategory] {
        listing.categories.filter { $0.parentID == nil && $0.kind == kind && !$0.isArchived }
    }

    private func liveSubcategories(of parentID: UUID) -> [TransactionCategory] {
        listing.subcategories(of: parentID).filter { !$0.isArchived }
    }

    // MARK: Reorder and Unarchive

    /// Drags top-level categories of the chosen kind into a new order.
    public func moveCategories(from offsets: IndexSet, to destination: Int) {
        var ids = topLevel(kind).map(\.id)
        ids = ids.moving(offsets, to: destination)
        perform { try useCases.categories.reorderCategories.reorder(ids) }
    }

    /// Drags a parent's subcategories into a new order; they reorder only within their parent.
    public func moveSubcategories(of parentID: UUID, from offsets: IndexSet, to destination: Int) {
        var ids = liveSubcategories(of: parentID).map(\.id)
        ids = ids.moving(offsets, to: destination)
        perform { try useCases.categories.reorderCategories.reorder(ids) }
    }

    /// Unarchiving a subcategory brings back its parent, but not the parent's other subcategories (D291.3).
    public func unarchive(_ id: UUID) {
        perform { try useCases.categories.archiveCategory.unarchive(id) }
    }

    // MARK: Delete (D19, D287)

    /// Asks how to delete the category.
    public func requestDelete(_ id: UUID) {
        guard let category = listing.category(id) else {
            return
        }
        do {
            let impact = try useCases.categories.deleteCategory.deletionImpact(of: id)
            // Only subcategories something uses are named (“including those in …”).
            let names = listing.subcategories(of: id).filter { listing.uses(of: $0.id) > 0 }.map(\.name)
            var sentences: [String]
            if impact.isUnused {
                sentences = [CategoryText.nothingUses]
                if impact.subcategoryCount > 0 {
                    sentences.append(CategoryText.deletesSubcategoriesToo(impact.subcategoryCount))
                }
            } else {
                sentences = [
                    CategoryText.usedBy(usedCount(impact), subcategoryNames: names),
                    CategoryText.archiveKeepsHistory,
                    CategoryText.movingDeletes(count: usedCount(impact), subcategoryCount: impact.subcategoryCount),
                ]
            }
            sentences.append(CategoryText.deletingCantBeUndone)
            deletePrompt = CategoryDeletePrompt(
                id: id,
                title: CategoryText.deleteTitle(category.name),
                message: CategoryText.sentences(sentences),
                isUnused: impact.isUnused,
            )
        } catch {
            failed()
        }
    }

    /// Archive, the default choice. It's reversed with Unarchive, so Undo is kept.
    @discardableResult
    public func archive(_ id: UUID) -> Bool {
        perform { try useCases.categories.deleteCategory.delete(id, choice: .archive) }
    }

    /// Deletes the category and its subcategories, leaving their transactions uncategorised. Not undoable.
    @discardableResult
    public func deleteLeavingUncategorised(_ id: UUID) -> Bool {
        removing { try useCases.categories.deleteCategory.delete(id, choice: .leaveUncategorised) }
    }

    /// Moves the transactions to `targetID`, then deletes the category and its subcategories. Not undoable.
    @discardableResult
    public func delete(_ id: UUID, movingTo targetID: UUID) -> Bool {
        removing { try useCases.categories.deleteCategory.delete(id, choice: .move(targetID: targetID)) }
    }

    /// The same-kind, unarchived categories outside the category's own subtree, in tree order. It reads the
    /// store, so only `makeTargetChoice` calls it, once, never a view body.
    public func moveTargets(forDeleting id: UUID) -> [CategoryRow] {
        targets { try useCases.categories.deleteCategory.moveTargets(forDeleting: id) }
    }

    public func moveHeader(forDeleting id: UUID) -> String {
        guard let category = listing.category(id) else {
            return ""
        }
        let subtree = [category] + listing.subcategories(of: id)
        let count = subtree.reduce(0) { $0 + listing.uses(of: $1.id) }
        return CategoryText.moveHeader(count: count, name: category.name, hasSubcategories: subtree.count > 1)
    }

    public func moveFooter(forDeleting id: UUID) -> String {
        guard let category = listing.category(id) else {
            return ""
        }
        let names = ([category] + listing.subcategories(of: id)).map(\.name)
        return CategoryText.sentences([
            CategoryText.onlyKindOffered(category.kind),
            CategoryText.deletedAfterMove(names),
        ])
    }

    private func usedCount(_ impact: CategoryDeletionImpact) -> Int {
        impact.transactionCount + impact.splitLineCount
    }

    // MARK: Merge (D19, D287, D291)

    /// The same-kind, unarchived categories `id` can merge into, in tree order. It reads the store, so only
    /// `makeTargetChoice` calls it, once, never a view body.
    public func mergeTargets(for id: UUID) -> [CategoryRow] {
        targets { try useCases.categories.mergeCategories.mergeTargets(for: id) }
    }

    public func mergeHeader(for id: UUID) -> String {
        guard let category = listing.category(id) else {
            return ""
        }
        return CategoryText.mergeHeader(name: category.name, count: listing.uses(of: id))
    }

    /// "25 transactions will use Food & Dining. Groceries is then deleted. Income categories can’t be merged
    /// with expense ones, so they aren’t listed. Merging can’t be undone." Budgets join it with #25.
    public func mergeFootnote(for id: UUID, into targetID: UUID?) -> String {
        guard let category = listing.category(id) else {
            return ""
        }
        var sentences: [String] = []
        if let targetID, let target = listing.category(targetID) {
            sentences.append(CategoryText.willUse(count: listing.uses(of: id), target: target.name))
            sentences.append(CategoryText.thenDeleted(category.name))
        }
        sentences.append(CategoryText.otherKindNotListed(category.kind))
        // Its subcategories go with it (D301), named only once a target is chosen.
        let subcategoryCount = listing.subcategories(of: id).count
        if subcategoryCount > 0, let targetID, let target = listing.category(targetID) {
            sentences.append(CategoryText.subcategoriesMove(count: subcategoryCount, to: target.name))
        }
        sentences.append(CategoryText.mergingCantBeUndone)
        return CategoryText.sentences(sentences)
    }

    /// Merges `id` into `targetID`, all or nothing. When two subcategories would share a name it's refused
    /// with D291.1's alert, and the sheet stays open to choose another target.
    @discardableResult
    public func merge(_ id: UUID, into targetID: UUID) -> Bool {
        do {
            try useCases.categories.mergeCategories.merge(id, into: targetID)
        } catch LedgerValidationError.subcategoryNamesClash(let clash) {
            // OK only; the sheet stays open so another target can be chosen (D291.1).
            alert = CategoryAlert(
                title: CategoryText.cantMergeTitle,
                message: CategoryText.mergeClash(
                    source: clash.sourceName,
                    survivor: clash.survivorName,
                    count: clash.count,
                    firstName: clash.firstClashingName,
                ),
            )
            return false
        } catch {
            failed()
            return false
        }
        didChange(removing: true)
        return true
    }

    // MARK: Editor

    /// The editor for a new top-level category of the chosen kind.
    public func makeNewCategory() -> CategoryEditorViewModel {
        CategoryEditorViewModel(mode: .add(kind: kind, parentID: nil), useCases: useCases, screen: self)
    }

    /// The editor for a new subcategory, under the first top-level category of the chosen kind.
    public func makeNewSubcategory() -> CategoryEditorViewModel {
        CategoryEditorViewModel(
            mode: .add(kind: kind, parentID: topLevel(kind).first?.id),
            useCases: useCases,
            screen: self,
        )
    }

    /// The Merge or Move To sheet's state, with its rows read once now (B1 on #155).
    public func makeTargetChoice(_ purpose: CategoryTargetChoice.Purpose) -> CategoryTargetChoice {
        CategoryTargetChoice(purpose: purpose, screen: self)
    }

    /// A row's tap: opens its editor sheet.
    public func openEditor(for id: UUID) {
        editor = makeEditor(for: id)
    }

    public func openNewCategory() {
        editor = makeNewCategory()
    }

    public func openNewSubcategory() {
        editor = makeNewSubcategory()
    }

    public func makeEditor(for id: UUID) -> CategoryEditorViewModel? {
        guard listing.category(id) != nil else {
            return nil
        }
        return CategoryEditorViewModel(mode: .edit(id), useCases: useCases, screen: self)
    }

    /// Whether Add Subcategory has a parent to offer.
    public var canAddSubcategory: Bool {
        !topLevel(kind).isEmpty
    }

    /// The top-level, unarchived categories of `kind`, for a new subcategory's Parent row.
    func parentRows(_ kind: CategoryKind) -> [CategoryRow] {
        topLevel(kind).map(row)
    }

    // MARK: Changes

    private func targets(_ read: () throws -> [TransactionCategory]) -> [CategoryRow] {
        guard let allowed = try? Set(read().map(\.id)) else {
            return []
        }
        var rows: [CategoryRow] = []
        for parent in listing.categories where parent.parentID == nil && parent.kind == kind {
            if allowed.contains(parent.id) {
                rows.append(row(parent))
            }
            rows += liveSubcategories(of: parent.id).filter { allowed.contains($0.id) }.map(row)
        }
        return rows
    }

    @discardableResult
    private func perform(_ change: () throws -> Void) -> Bool {
        do {
            try change()
        } catch {
            failed()
            load()
            return false
        }
        didChange(removing: false)
        return true
    }

    private func removing(_ change: () throws -> Void) -> Bool {
        do {
            try change()
        } catch {
            failed()
            return false
        }
        didChange(removing: true)
        return true
    }

    func didChange(removing: Bool) {
        if removing {
            onRemoval()
        }
        load()
        changed()
    }

    private func failed() {
        alert = CategoryAlert(title: CategoryText.couldntSaveTitle, message: CategoryText.nothingChanged)
    }
}

/// The use cases the category screens need, from the composition root.
@MainActor
public struct CategoryScreenUseCases {
    public var load: any LoadCategoriesUseCase
    public var edit: any EditCategoryUseCase
    public var categories: CategoryUseCases

    public init(
        load: any LoadCategoriesUseCase,
        edit: any EditCategoryUseCase,
        categories: CategoryUseCases,
    ) {
        self.load = load
        self.edit = edit
        self.categories = categories
    }
}

extension Array {
    /// The array with the elements at `offsets` moved to before `destination`, as a List's drag reports it.
    func moving(_ offsets: IndexSet, to destination: Int) -> [Element] {
        let moved = offsets.filter { indices.contains($0) }.map { self[$0] }
        var rest: [Element] = []
        var insertAt = 0
        for (index, element) in enumerated() where !offsets.contains(index) {
            if index < destination {
                insertAt += 1
            }
            rest.append(element)
        }
        rest.insert(contentsOf: moved, at: insertAt)
        return rest
    }
}
