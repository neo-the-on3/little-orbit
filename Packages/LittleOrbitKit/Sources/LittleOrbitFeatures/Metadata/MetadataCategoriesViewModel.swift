import Foundation
import LittleOrbitDomain
import Observation

/// One row of the Mac Metadata manager's Categories table (#24 design, Mac metadata row): the chip and name,
/// the kind, and how many transactions and split lines use the category itself.
public struct MetadataCategoryRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let kind: CategoryKind
    public let kindName: String
    public let used: Int
    public let symbolName: String
    public let hue: CategoryHue
    public let isSubcategory: Bool
    /// What VoiceOver reads for the name: "Groceries, under Food & Dining" for a subcategory, so it can be told
    /// apart in the flat table, the same wording as the iOS form (UI Designer, #169); the name otherwise.
    public let spokenName: String
}

/// Whether the toolbar's Merge can open, and why not (#24 design, Mac merge and mixed kinds).
public enum MetadataMergeAvailability: Equatable, Sendable {
    /// Two categories of the same kind are selected.
    case available
    /// An expense and an income category are selected.
    case mixedKinds
    /// Fewer or more than two categories are selected. A merge is one pair, all or nothing (D287.4).
    case needsTwo
}

/// The Mac Metadata manager's Categories table (#24 part 5): one flat table of both kinds in the tree's order,
/// multi-select with Merge for two of the same kind, inline rename, the Edit Category sheet, Add, Delete with
/// the same choices as iOS, and an Archived group with Unarchive (D302). It wraps the iOS screen model, so the
/// rules, the copy and the use cases are the same; it depends only on use-case protocols through it. The Mac
/// has no parent control in the MVP (D287.1). Merge and delete aren't Undo steps (D287.2).
@MainActor
@Observable
public final class MetadataCategoriesViewModel {
    /// The shared category screen model: the listing, the editor, the delete and unarchive prompts, alerts.
    public let screen: CategoriesViewModel
    /// The selected rows.
    public var selection: Set<UUID> = [] {
        didSet { updateSelectionOrder() }
    }
    /// The selected rows in the order they were selected, for Merge's Keep on a tie (D304.5): a `Table`
    /// selection is an unordered set. Rows selected together, such as by Shift-click, follow the table's order.
    public private(set) var selectionOrder: [UUID] = []
    /// The Merge 2 Categories sheet on show.
    public var merge: MetadataCategoryMerge?
    /// The delete's Move To sheet on show.
    public var moveChoice: CategoryTargetChoice?
    /// The category being renamed in its row, with the editor that checks and saves the name.
    public private(set) var renaming: CategoryEditorViewModel?

    public init(screen: CategoriesViewModel) {
        self.screen = screen
    }

    // MARK: Reading

    /// Reads the categories and drops a selection whose category is gone or archived.
    public func load() {
        screen.load()
        let live = Set(rows.map(\.id))
        selection.formIntersection(live)
        if let id = renaming?.categoryID, !live.contains(id) {
            renaming = nil
        }
    }

    /// Every live category, expense first, then income: each top-level category followed by its unarchived
    /// subcategories, in the tree's order. The Mac table is flat (UI Designer, #24 Mac check).
    public var rows: [MetadataCategoryRow] {
        CategoryKind.allCases.flatMap { kind in
            screen.topLevel(kind)
                .flatMap { parent in
                    [row(parent)] + screen.liveSubcategories(of: parent.id).map(row)
                }
        }
    }

    /// Archived categories of both kinds, expense first, each kind as the iOS Archived section lists it.
    public var archivedRows: [CategoryRow] {
        CategoryKind.allCases.flatMap { screen.archivedRows(of: $0) }
    }

    private func updateSelectionOrder() {
        let kept = selectionOrder.filter(selection.contains)
        let added = selection.subtracting(kept)
        guard kept.count != selectionOrder.count || !added.isEmpty else {
            return
        }
        let tableOrder = rows.map(\.id)
        let addedInTableOrder = tableOrder.filter(added.contains)
        // An id that isn't a row any more still counts, after the rows, so the order always matches the set.
        selectionOrder =
            kept + addedInTableOrder + added.subtracting(addedInTableOrder).sorted { $0.uuidString < $1.uuidString }
    }

    private func row(_ category: TransactionCategory) -> MetadataCategoryRow {
        MetadataCategoryRow(
            id: category.id,
            name: category.name,
            kind: category.kind,
            kindName: CategoryText.kindName(category.kind),
            used: screen.listing.uses(of: category.id),
            symbolName: CategoryAppearance.symbol(of: category),
            hue: screen.hue(of: category),
            isSubcategory: category.parentID != nil,
            spokenName: TransactionCategoryGroup.spokenValue(
                of: category.id,
                in: [category] + (category.parentID.flatMap(screen.category).map { [$0] } ?? []),
            ),
        )
    }

    private var selectedCategories: [TransactionCategory] {
        rows.filter { selection.contains($0.id) }.compactMap { screen.category($0.id) }
    }

    /// The one selected category, for Delete, Rename and Add Subcategory.
    public var singleSelection: UUID? {
        selection.count == 1 ? selection.first : nil
    }

    // MARK: Status bar

    /// "2 selected", "2 selected · 1 expense, 1 income" for both kinds, the rename hint or the rename's name
    /// error while a row is renamed, and nothing with no selection.
    public var statusText: String {
        if let renaming {
            return renaming.nameError ?? MetadataText.renameHint(isSubcategory: renaming.isSubcategory)
        }
        guard !selection.isEmpty else {
            return ""
        }
        let selected = PayeeText.selected(selection.count)
        guard mergeAvailability == .mixedKinds else {
            return selected
        }
        let expenses = selectedCategories.filter { $0.kind == .expense }.count
        return MetadataText.mixedSelection(
            selected,
            expenses: expenses,
            income: selectedCategories.count - expenses,
        )
    }

    // MARK: Merge (D19, D287, D291)

    /// Whether Merge can open for the selection.
    public var mergeAvailability: MetadataMergeAvailability {
        mergeAvailability(of: selection)
    }

    /// Whether Merge can open for these rows, such as the rows a context menu was opened on.
    public func mergeAvailability(of ids: Set<UUID>) -> MetadataMergeAvailability {
        let categories = rows.filter { ids.contains($0.id) }
        if Set(categories.map(\.kind)).count > 1 {
            return .mixedKinds
        }
        return categories.count == 2 ? .available : .needsTwo
    }

    /// The disabled Merge button's tooltip; `nil` while Merge is available.
    public var mergeHelp: String? {
        switch mergeAvailability {
        case .available: nil
        case .mixedKinds: MetadataText.mixedKindsHelp
        case .needsTwo: MetadataText.selectTwoHelp
        }
    }

    /// Opens Merge 2 Categories for the two selected categories.
    public func startMerge() {
        guard mergeAvailability == .available else {
            return
        }
        merge = MetadataCategoryMerge(
            ids: rows.map(\.id).filter(selection.contains),
            selectionOrder: selectionOrder,
            screen: screen,
        )
    }

    // MARK: Delete (D19, D287)

    /// Asks how to delete the one selected category, with the same alert as iOS.
    public func requestDelete() {
        guard let id = singleSelection else {
            return
        }
        screen.requestDelete(id)
    }

    /// The delete alert's Move to Another Category…: the same-kind targets, read once.
    public func startMove(_ id: UUID) {
        screen.deletePrompt = nil
        // The targets are read for the category's own kind (D291.4); the Mac has no kind tab.
        if let category = screen.category(id) {
            screen.kind = category.kind
        }
        moveChoice = screen.makeTargetChoice(.move(id))
    }

    // MARK: Rename in the row

    /// Starts renaming a row in place. Return saves, Esc cancels (#24 design, Mac inline rename).
    public func beginRename(_ id: UUID) {
        guard rows.contains(where: { $0.id == id }) else {
            return
        }
        selection = [id]
        renaming = screen.makeEditor(for: id)
    }

    /// The name being typed in the row.
    public var renameText: String {
        get { renaming?.name ?? "" }
        set { renaming?.name = newValue }
    }

    /// Return: saves the new name. An unchanged name just ends the rename. A name error keeps the row
    /// editing and shows in the status bar (D295.4); a failed save shows “Couldn’t Save Changes” (D295.5).
    @discardableResult
    public func commitRename() -> Bool {
        guard let renaming else {
            return false
        }
        guard renaming.hasUnsavedEdits else {
            self.renaming = nil
            return true
        }
        if renaming.save() {
            self.renaming = nil
            return true
        }
        if let alert = renaming.alert {
            screen.alert = alert
            renaming.alert = nil
            self.renaming = nil
        }
        return false
    }

    /// Esc: ends the rename and keeps the old name.
    public func cancelRename() {
        renaming = nil
    }

    // MARK: Editor and Add

    /// The row's Edit Category… sheet.
    public func openEditor(for id: UUID) {
        renaming = nil
        screen.openEditor(for: id)
    }

    /// Add Expense Category or Add Income Category: a new top-level category of that kind.
    public func openNewCategory(_ kind: CategoryKind) {
        renaming = nil
        screen.editor = screen.makeNewCategory(kind: kind, parentID: nil)
    }

    /// The parent Add Subcategory adds under: the selected top-level category, or the selected subcategory's
    /// parent. The Mac has no Parent control (D287.1), so it comes from the selection.
    public var subcategoryParent: TransactionCategory? {
        guard let id = singleSelection, let category = screen.category(id), !category.isArchived else {
            return nil
        }
        return category.parentID.flatMap(screen.category) ?? category
    }

    public func openNewSubcategory() {
        guard let parent = subcategoryParent else {
            return
        }
        renaming = nil
        screen.editor = screen.makeNewCategory(kind: parent.kind, parentID: parent.id)
    }
}
