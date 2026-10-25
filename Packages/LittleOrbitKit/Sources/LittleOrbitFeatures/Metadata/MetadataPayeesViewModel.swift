import Foundation
import LittleOrbitDomain
import Observation

/// One row of the Mac Metadata manager's Payees table (#24 design, Mac payees): the name, the last-used
/// category's name (empty when there's none), and how many transactions use the payee.
public struct MetadataPayeeRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let lastCategory: String
    public let used: Int
}

/// The Mac Metadata manager's Payees table (#24 part 5): every payee by name, multi-select with Merge for two
/// or more, and renaming in the row. It wraps the iOS screen model, so the rules, the copy and the use cases
/// are the same; it depends only on use-case protocols through it. As on iOS, payees aren't added or deleted
/// here: they come from transactions. A merge isn't an Undo step (D287.2).
@MainActor
@Observable
public final class MetadataPayeesViewModel {
    /// The shared payee screen model: the listing, the selection, the survivor and alerts.
    public let screen: PayeesViewModel
    /// The Merge N Payees sheet on show.
    public var merge: MetadataPayeeMerge?
    /// The payee being renamed in its row, with the editor that checks and saves the name.
    public private(set) var renaming: PayeeEditorViewModel?

    public init(screen: PayeesViewModel) {
        self.screen = screen
    }

    // MARK: Reading

    /// Reads the payees; a selected or renamed payee that's gone leaves the selection and the rename.
    public func load() {
        screen.load()
        if let id = renaming?.payeeID, screen.payee(id) == nil {
            renaming = nil
        }
    }

    /// Every payee, by name.
    public var rows: [MetadataPayeeRow] {
        screen.rows.map { row in
            MetadataPayeeRow(
                id: row.id,
                name: row.name,
                lastCategory: screen.payee(row.id).flatMap(screen.listing.lastUsedCategory)?.name ?? "",
                used: screen.listing.uses(of: row.id),
            )
        }
    }

    public var hasPayees: Bool {
        screen.hasPayees
    }

    /// The selected rows, shared with the screen model that merges them.
    public var selection: Set<UUID> {
        get { screen.selection }
        set { screen.selection = newValue }
    }

    // MARK: Status bar

    /// "3 selected", the rename hint or the rename's name error while a row is renamed, and nothing with no
    /// selection.
    public var statusText: String {
        if let renaming {
            return renaming.nameError ?? MetadataText.payeeRenameHint
        }
        return selection.isEmpty ? "" : screen.selectedText
    }

    // MARK: Merge (D287, D291.5, D304)

    /// Merge needs two or more payees.
    public var canMerge: Bool {
        canMerge(selection)
    }

    /// Whether Merge can open for these rows, such as the rows a context menu was opened on.
    public func canMerge(_ ids: Set<UUID>) -> Bool {
        rows.filter { ids.contains($0.id) }.count >= 2
    }

    /// The disabled Merge button's tooltip; `nil` while Merge is available.
    public var mergeHelp: String? {
        canMerge ? nil : MetadataText.selectPayeesHelp
    }

    /// Opens Merge N Payees for the selected payees, named in the table's order. Keep name: follows the iOS
    /// rule (#156, D305.3): the payee most transactions use, then the one used most recently, then the first
    /// by name.
    public func startMerge() {
        guard canMerge else {
            return
        }
        renaming = nil
        screen.startMerge()
        merge = MetadataPayeeMerge(names: rows.filter { selection.contains($0.id) }.map(\.name), owner: self)
    }

    /// Ends the merge after it's done.
    func endMerge() {
        merge = nil
    }

    // MARK: Rename in the row

    /// Starts renaming a row in place. Return saves, Esc cancels (#24 design, Mac inline rename).
    public func beginRename(_ id: UUID) {
        guard let editor = screen.makeEditor(for: id) else {
            return
        }
        selection = [id]
        renaming = editor
    }

    /// The name being typed in the row.
    public var renameText: String {
        get { renaming?.name ?? "" }
        set { renaming?.name = newValue }
    }

    /// Return: saves the new name. An unchanged name, ignoring outer spaces, just ends the rename. A name
    /// error keeps the row editing and shows in the status bar (D295.4, D297.7); a failed save shows
    /// “Couldn’t Save Changes” and ends the rename.
    @discardableResult
    public func commitRename() -> Bool {
        guard let renaming else {
            return false
        }
        if renaming.save() {
            self.renaming = nil
            return true
        }
        if let alert = renaming.alert {
            screen.alert = alert
            renaming.alert = nil
            self.renaming = nil
            return false
        }
        guard renaming.nameError == nil else {
            return false
        }
        // Nothing to save: the name is the same as before, apart from outer spaces.
        self.renaming = nil
        return true
    }

    /// Esc: ends the rename and keeps the old name.
    public func cancelRename() {
        renaming = nil
    }
}

/// The Mac Merge N Payees sheet (#24 design, Mac payees merge): the names in the table's order, a Keep name:
/// pop-up and the iOS footnote (D297.3). A failed merge shows “Couldn’t Save Changes” on this sheet, which
/// stays open, and nothing changes. It reads through the payees table's screen model.
@MainActor
@Observable
public final class MetadataPayeeMerge: Identifiable {
    public let title: String
    public let message: String
    /// The sheet's own alert, so the window under it never shows the same one.
    public var alert: CategoryAlert?

    @ObservationIgnored private weak var owner: MetadataPayeesViewModel?

    init(names: [String], owner: MetadataPayeesViewModel) {
        title = MetadataText.payeeMergeTitle(names.count)
        message = MetadataText.payeeMergeMessage(names)
        self.owner = owner
    }

    public nonisolated var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    /// The payees whose name can be kept, in the table's order.
    public var keepOptions: [PayeeRow] {
        owner?.screen.mergeRows ?? []
    }

    /// The payee whose name is kept; the others are merged into it.
    public var keptID: UUID? {
        get { owner?.screen.survivorID }
        set { owner?.screen.survivorID = newValue }
    }

    /// "7 transactions will use Parcel Point. … Merging can’t be undone." (D287.3, D297.3)
    public var footnote: String {
        owner?.screen.mergeFootnote ?? CategoryText.mergingCantBeUndone
    }

    public var canMerge: Bool {
        keptID != nil && owner?.canMerge == true
    }

    /// Merges the payees into the kept one, all or nothing (D291.5).
    @discardableResult
    public func confirm() -> Bool {
        guard let owner else {
            return false
        }
        if owner.screen.merge() {
            owner.endMerge()
            return true
        }
        alert = owner.screen.alert
        owner.screen.alert = nil
        return false
    }
}
