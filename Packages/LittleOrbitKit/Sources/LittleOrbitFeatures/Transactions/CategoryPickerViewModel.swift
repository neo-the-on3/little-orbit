import Foundation
import LittleOrbitDomain
import Observation

/// The use cases the transaction form's category picker needs, from the composition root.
@MainActor
public struct CategoryPickingUseCases {
    public var load: any LoadCategoriesUseCase
    public var edit: any EditCategoryUseCase

    public init(load: any LoadCategoriesUseCase, edit: any EditCategoryUseCase) {
        self.load = load
        self.edit = edit
    }
}

/// The transaction form's category picker on iOS (#24 frames 16:7540 and 16:7702): Uncategorised, then the
/// unarchived categories of the transaction's kind, each parent with its subcategories, a search field, and
/// a Create row for a typed name nothing matches. Done applies the checked choice; Cancel leaves the form as
/// it was.
///
/// It reads the store once when it opens and again only after Create; the lists the sheet shows are built
/// from that state, so drawing the sheet never reads the store.
@MainActor
@Observable
public final class CategoryPickerViewModel {
    public let kind: CategoryKind
    /// What the search field holds.
    public var query = ""
    /// The checked row: a category, or `nil` for Uncategorised.
    public private(set) var selection: UUID?
    public var alert: CategoryAlert?
    /// The categories as read when the sheet opened or after Create.
    public private(set) var listing = CategoryListing(categories: [], usage: [:])
    /// Every row the sheet can show, built once per read.
    private var allGroups: [CategoryRowGroup] = []
    private var keptRow: CategoryRow?

    @ObservationIgnored private let useCases: CategoryPickingUseCases
    @ObservationIgnored private let changed: () -> Void
    /// The transaction's own category, shown under Archived when it's archived, so opening the picker doesn't
    /// hide what the transaction already uses.
    @ObservationIgnored private let currentID: UUID?

    public init(
        kind: CategoryKind,
        selection: UUID?,
        useCases: CategoryPickingUseCases,
        changed: @escaping () -> Void = {},
    ) {
        self.kind = kind
        self.selection = selection
        self.currentID = selection
        self.useCases = useCases
        self.changed = changed
        load()
    }

    private func load() {
        do {
            listing = try useCases.load.listing()
        } catch {
            alert = CategoryAlert(title: CategoryText.couldntLoadTitle, message: CategoryText.tryAgain)
        }
        let tops = listing.categories.filter { $0.parentID == nil && $0.kind == kind && !$0.isArchived }
        allGroups = tops.map { parent in
            CategoryRowGroup(
                parent: listing.pickerRow(parent),
                subcategories: listing.subcategories(of: parent.id).filter { !$0.isArchived }.map(listing.pickerRow),
            )
        }
        let shown = Set(allGroups.flatMap { [$0.parent.id] + $0.subcategories.map(\.id) })
        keptRow = currentID.flatMap(listing.category)
            .flatMap { $0.kind == kind && !shown.contains($0.id) ? listing.pickerRow($0) : nil }
    }

    // MARK: Text

    public var title: String { CategoryPickerText.title }
    public var searchPrompt: String { CategoryPickerText.searchPrompt }
    public var uncategorisedTitle: String { CategoryPickerText.uncategorised }
    public var uncategorisedSubtitle: String { CategoryPickerText.noCategory }
    /// The section header over the categories: “Expense” or “Income”.
    public var sectionTitle: String { CategoryText.kindName(kind) }
    public var archivedTitle: String { CategoryText.archived }

    // MARK: Rows

    private var key: String { Self.fold(query) }

    /// Uncategorised shows until something is typed (16:7702).
    public var showsUncategorised: Bool { key.isEmpty }

    /// The categories of the transaction's kind. While searching, a parent shows with its matching
    /// subcategories, or with all of them when its own name matches. Matching ignores case and accents.
    public var groups: [CategoryRowGroup] {
        let key = key
        guard !key.isEmpty else {
            return allGroups
        }
        return allGroups.compactMap { group in
            if Self.fold(group.parent.name).contains(key) {
                return group
            }
            let matching = group.subcategories.filter { Self.fold($0.name).contains(key) }
            return matching.isEmpty ? nil : CategoryRowGroup(parent: group.parent, subcategories: matching)
        }
    }

    /// The transaction's own archived category, so it stays visible and checked.
    public var archivedRow: CategoryRow? {
        guard let keptRow, key.isEmpty || Self.fold(keptRow.name).contains(key) else {
            return nil
        }
        return keptRow
    }

    /// The typed name, trimmed, when no category the sheet shows has that name (ignoring case and outer
    /// spaces): then the Create row offers it (16:7702). An existing name is reused, never duplicated.
    public var createName: String? {
        let name = EditorName.trimmed(query)
        guard !name.isEmpty else {
            return nil
        }
        let key = EditorName.key(name)
        let rows = allGroups.flatMap { [$0.parent] + $0.subcategories } + (keptRow.map { [$0] } ?? [])
        return rows.contains { EditorName.key($0.name) == key } ? nil : name
    }

    /// Why Create can't use the typed name: an archived category of the transaction's kind at the top level,
    /// where Create adds it, already has it, trimmed and ignoring case (D303, D299's scope). It quotes the
    /// stored name. Typing is editing the name, so it shows as soon as the name matches (D151), under the
    /// Create row, which is then off; there's no Unarchive here.
    public var createError: String? {
        guard let name = createName else {
            return nil
        }
        let key = EditorName.key(name)
        return listing.categories
            .first { $0.isArchived && $0.parentID == nil && $0.kind == kind && EditorName.key($0.name) == key }
            .map { CategoryPickerText.archivedName($0.name) }
    }

    public var createTitle: String? { createName.map(CategoryPickerText.create) }
    public var createDetail: String { CategoryPickerText.newKind(kind) }

    // MARK: Choosing

    public func select(_ id: UUID?) {
        selection = id
    }

    /// Adds the typed name as a top-level category of the transaction's kind, with the icon and colour Add
    /// Category starts with, checks it and clears the search, so Done puts it on the form. The form's other
    /// fields aren't touched. An archived category's name is refused with `createError`, without reading or
    /// writing the store; a name the ledger refuses shows in an alert. Either way nothing changes.
    @discardableResult
    public func create() -> Bool {
        guard let name = createName, createError == nil else {
            return false
        }
        if let problem = EditorName.lengthProblem(name) {
            alert = CategoryAlert(title: CategoryText.couldntSaveTitle, message: problem)
            return false
        }
        let edit = CategoryEdit(
            name: name,
            iconName: CategoryAppearance.fallbackSymbol,
            colorHex: CategoryHue.gray.hex,
            parentID: nil,
        )
        do {
            let id = try useCases.edit.add(edit, kind: kind)
            load()
            selection = id
            query = ""
            changed()
            return true
        } catch LedgerValidationError.duplicateCategoryName {
            alert = CategoryAlert(title: CategoryText.couldntSaveTitle, message: CategoryText.duplicateName(name))
        } catch LedgerValidationError.nameTooLong {
            alert = CategoryAlert(title: CategoryText.couldntSaveTitle, message: CategoryText.nameTooLong)
        } catch {
            alert = CategoryAlert(title: CategoryText.couldntSaveTitle, message: CategoryText.nothingChanged)
        }
        return false
    }

    /// The checked category as read, for the form to show; `nil` for Uncategorised.
    public var selectedCategory: TransactionCategory? {
        selection.flatMap(listing.category)
    }

    private static func fold(_ text: String) -> String {
        EditorName.trimmed(text).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

extension CategoryListing {
    /// A picker row: the chip in the category's colour (a subcategory shows its parent's), the name, and the
    /// Categories screen's subtitle (D303).
    func pickerRow(_ category: TransactionCategory) -> CategoryRow {
        CategoryRow(
            id: category.id,
            name: category.name,
            subtitle: rowSubtitle(of: category),
            symbolName: CategoryAppearance.symbol(of: category),
            hue: CategoryAppearance.hue(of: category.parentID.flatMap(self.category) ?? category),
            isSubcategory: category.parentID != nil,
        )
    }
}
