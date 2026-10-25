import Foundation
import LittleOrbitDomain
import Observation

/// The category and subcategory editor (#24 design, Edit Subcategory): name, icon, colour and, for a
/// subcategory, its parent (D287.1). A subcategory always has its parent's kind (#11).
@MainActor
@Observable
public final class CategoryEditorViewModel {
    public enum Mode: Equatable, Sendable {
        /// A new top-level category, or a subcategory under `parentID`.
        case add(kind: CategoryKind, parentID: UUID?)
        case edit(UUID)
    }

    public let mode: Mode
    public let kind: CategoryKind
    public let isSubcategory: Bool
    public var name: String {
        didSet {
            nameEdited = true
            savedNameError = nil
        }
    }
    public var symbolName: String
    /// The colour. A subcategory always shows its parent's (UI Designer's #155 ruling), so it follows the
    /// Parent row and has no colour control.
    public var hue: CategoryHue
    /// The parent of a subcategory.
    public var parentID: UUID? {
        didSet {
            if let parent = parentID.flatMap({ screen?.category($0) }) {
                hue = CategoryAppearance.hue(of: parent)
            }
        }
    }
    public var alert: CategoryAlert?
    /// Set once the name field is edited, or a save is tried: name errors show only after that (D151).
    public private(set) var nameEdited = false
    /// A name error the save itself reported, shown until the name changes.
    private var savedNameError: String?

    @ObservationIgnored private let useCases: CategoryScreenUseCases
    @ObservationIgnored private weak var screen: CategoriesViewModel?
    /// The Parent row's choices: unarchived top-level categories of the same kind, in the tree's order
    /// (D287.1, D291.4). Worked out once from the screen's loaded tree when the editor opens, so typing or
    /// re-rendering never reads the store (B1 on #155).
    public private(set) var parentOptions: [CategoryRow] = []
    /// A subcategory's stored colour, saved back untouched: its parent's colour is what shows.
    @ObservationIgnored private var storedColorHex: String?
    /// What the editor opened with, to tell unsaved edits apart.
    @ObservationIgnored private var original = CategoryEdit(name: "", iconName: nil, colorHex: nil, parentID: nil)

    init(mode: Mode, useCases: CategoryScreenUseCases, screen: CategoriesViewModel) {
        self.mode = mode
        self.useCases = useCases
        self.screen = screen
        switch mode {
        case .add(let kind, let parentID):
            let parent = parentID.flatMap(screen.category)
            self.kind = parent?.kind ?? kind
            isSubcategory = parentID != nil
            name = ""
            // A subcategory shows its parent's colour; a new category is gray until one is chosen.
            symbolName = CategoryAppearance.fallbackSymbol
            hue = parent.map(CategoryAppearance.hue) ?? .gray
            self.parentID = parentID
        case .edit(let id):
            let category = screen.category(id)
            kind = category?.kind ?? .expense
            isSubcategory = category?.parentID != nil
            name = category?.name ?? ""
            symbolName = category.map(CategoryAppearance.symbol) ?? CategoryAppearance.fallbackSymbol
            let parent = category?.parentID.flatMap(screen.category)
            hue = (parent ?? category).map(CategoryAppearance.hue) ?? .gray
            parentID = category?.parentID
            storedColorHex = category?.colorHex
        }
        original = edit
        if isSubcategory {
            parentOptions = screen.parentRows(kind)
        }
    }

    private var edit: CategoryEdit {
        CategoryEdit(
            name: name,
            iconName: symbolName,
            colorHex: isSubcategory ? storedColorHex : hue.hex,
            parentID: parentID,
        )
    }

    /// Whether Cancel or a swipe down would lose edits, so the sheet asks “Discard Changes?” first (D300.1). A new
    /// category or subcategory has none until something is entered or changed: its name, icon, colour or parent.
    public var hasUnsavedEdits: Bool {
        edit != original
    }

    public var isNew: Bool {
        if case .add = mode {
            return true
        }
        return false
    }

    public var categoryID: UUID? {
        if case .edit(let id) = mode {
            return id
        }
        return nil
    }

    public var title: String {
        CategoryText.editorTitle(isNew: isNew, isSubcategory: isSubcategory)
    }

    /// "Expense (from parent)" for a subcategory, "Expense" for a category.
    public var kindValue: String {
        isSubcategory ? CategoryText.kindFromParent(kind) : CategoryText.kindName(kind)
    }

    public var footnote: String {
        isSubcategory ? CategoryText.subcategoryFootnote : CategoryText.categoryFootnote
    }

    /// The editor's icons, each with its catalog name, with the category's own first as “Current Icon” when
    /// it isn't one of them (D292.2).
    public var symbolOptions: [CategorySymbol] {
        let listed = CategoryAppearance.symbols.map { CategorySymbol(symbol: $0) }
        return CategoryAppearance.symbols.contains(symbolName) ? listed : [CategorySymbol(symbol: symbolName)] + listed
    }

    /// The Icon row's value and the chip's VoiceOver name.
    public var symbolLabel: String {
        CategorySymbol(symbol: symbolName).name
    }

    public func colourName(_ hue: CategoryHue) -> String {
        CategoryText.colourName(hue)
    }

    /// Save is off while the name is invalid or a subcategory has no parent (D151), and, when editing, until
    /// something changes.
    public var canSave: Bool {
        nameProblem == nil && savedNameError == nil && (!isSubcategory || parentID != nil)
            && (isNew || hasUnsavedEdits)
    }

    /// The error under the name field (D295.4), once the field has been edited.
    public var nameError: String? {
        guard nameEdited else {
            return nil
        }
        return nameProblem ?? savedNameError
    }

    /// Empty, longer than 100 characters (graphemes, D39), or another category's name at the same level: the
    /// same parent for a subcategory, the same kind for a top-level category, ignoring case and outer spaces.
    private var nameProblem: String? {
        if let problem = EditorName.lengthProblem(name) {
            return problem
        }
        let key = EditorName.key(name)
        let taken = screen?.listing.categories
            .first { other in
                other.id != categoryID
                    && other.parentID == parentID
                    && (parentID != nil || other.kind == kind)
                    && EditorName.key(other.name) == key
            }
        // It quotes the other category's stored name, not what was typed.
        return taken.map { CategoryText.duplicateName($0.name) }
    }

    /// The stored name of the category at this level that the ledger says has the name, for its error.
    private var clashingName: String {
        let key = EditorName.key(name)
        let other = screen?.listing.categories
            .first { other in
                other.id != categoryID
                    && other.parentID == parentID
                    && (parentID != nil || other.kind == kind)
                    && EditorName.key(other.name) == key
            }
        return other?.name ?? EditorName.trimmed(name)
    }

    /// Saves in one change. A name the ledger rejects shows under the field; any other failure shows
    /// “Couldn’t Save Changes” and nothing changes (D295.5).
    @discardableResult
    public func save() -> Bool {
        nameEdited = true
        guard canSave else {
            return false
        }
        do {
            switch mode {
            case .add:
                _ = try useCases.edit.add(edit, kind: kind)
            case .edit(let id):
                try useCases.edit.save(id, edit)
            }
        } catch let error as LedgerValidationError {
            if let message = nameMessage(for: error) {
                savedNameError = message
            } else {
                alert = CategoryAlert(title: CategoryText.couldntSaveTitle, message: CategoryText.nothingChanged)
            }
            return false
        } catch {
            alert = CategoryAlert(title: CategoryText.couldntSaveTitle, message: CategoryText.nothingChanged)
            return false
        }
        screen?.didChange(removing: false)
        return true
    }

    private func nameMessage(for error: LedgerValidationError) -> String? {
        switch error {
        case .invalidName: CategoryText.emptyName
        case .nameTooLong: CategoryText.nameTooLong
        case .duplicateCategoryName: CategoryText.duplicateName(clashingName)
        default: nil
        }
    }
}

/// An editor is shown in a sheet keyed by its own identity, on iOS and on the Mac.
extension CategoryEditorViewModel: Identifiable {
    public nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
