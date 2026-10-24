import Foundation
import LittleOrbitDomain
import Observation

/// One row of the payee list or the Merge Payees sheet.
public struct PayeeRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    /// "Shopping · 40": the last-used category and how many transactions use the payee, or "40 transactions"
    /// when it has no last-used category.
    public let detail: String
    /// VoiceOver's reading of `detail`: "Shopping, 40 transactions".
    public let spokenDetail: String
    /// "40 transactions", for the Merge Payees rows.
    public let transactions: String
}

/// iOS Settings › Payees (#24 design: list, select mode, merge with a name to keep). It lists every payee with
/// its last-used category, renames one, and merges several into the one whose name is kept. It depends only on
/// use-case protocols. A merge isn't an Undo step; after one, `onRemoval` clears this window's Undo and Redo
/// history (D287.2, D287.4).
@MainActor
@Observable
public final class PayeesViewModel {
    public private(set) var listing = PayeeListing(payees: [], usage: [:], categories: [])
    public var searchText = ""
    /// The payees chosen in select mode.
    public var selection: Set<UUID> = []
    /// The payee whose name the merge keeps.
    public var survivorID: UUID?
    /// A failed load or change.
    public var alert: CategoryAlert?
    /// The editor sheet on show.
    public var editor: PayeeEditorViewModel?
    /// Clears this window's Undo and Redo history; the screen sets it (D287.4).
    @ObservationIgnored public var onRemoval: () -> Void = {}

    @ObservationIgnored private let useCases: PayeeScreenUseCases
    @ObservationIgnored private let changed: () -> Void

    public init(useCases: PayeeScreenUseCases, changed: @escaping () -> Void = {}) {
        self.useCases = useCases
        self.changed = changed
    }

    // MARK: Reading

    public func load() {
        do {
            listing = try useCases.load.listing()
        } catch {
            alert = PayeeText.loadFailed
        }
        selection.formIntersection(listing.payees.map(\.id))
        if let survivorID, !selection.contains(survivorID) {
            self.survivorID = nil
        }
    }

    /// Every payee, by name, or those whose name contains the search text.
    public var rows: [PayeeRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return sorted(listing.payees)
            .filter { query.isEmpty || $0.name.localizedStandardContains(query) }
            .map(row)
    }

    public var hasPayees: Bool {
        !listing.payees.isEmpty
    }

    public func payee(_ id: UUID) -> Payee? {
        listing.payee(id)
    }

    private func row(_ payee: Payee) -> PayeeRow {
        let count = listing.uses(of: payee.id)
        let transactions = PayeeText.transactions(count)
        let category = listing.lastUsedCategory(of: payee)?.name
        return PayeeRow(
            id: payee.id,
            name: payee.name,
            detail: category.map { PayeeText.detail(category: $0, count: count) } ?? transactions,
            spokenDetail: category.map { PayeeText.spokenDetail(category: $0, count: count) } ?? transactions,
            transactions: transactions,
        )
    }

    private func sorted(_ payees: [Payee]) -> [Payee] {
        payees.sorted { lhs, rhs in
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : order == .orderedAscending
        }
    }

    // MARK: Select and merge (D287, D291.5)

    /// "2 selected".
    public var selectedText: String {
        PayeeText.selected(selection.count)
    }

    /// Merge needs two or more payees.
    public var canMerge: Bool {
        selection.count >= 2
    }

    /// Opens the merge: it keeps the name of the chosen payee most transactions use, then the one used most
    /// recently, then the first by name.
    public func startMerge() {
        survivorID =
            selectedPayees.max { lhs, rhs in
                let (lhsCount, rhsCount) = (listing.uses(of: lhs.id), listing.uses(of: rhs.id))
                if lhsCount != rhsCount {
                    return lhsCount < rhsCount
                }
                return (lhs.lastUsedAt ?? .distantPast) < (rhs.lastUsedAt ?? .distantPast)
            }?
            .id
    }

    /// The chosen payees, by name, for the Merge Payees sheet.
    public var mergeRows: [PayeeRow] {
        selectedPayees.map(row)
    }

    private var selectedPayees: [Payee] {
        sorted(listing.payees.filter { selection.contains($0.id) })
    }

    /// "52 transactions will use Parcel Point. PARCELPOINT.IN is removed from lists, autocomplete and reports.
    /// Parcel Point keeps the most recent last-used category (Shopping). Merging can’t be undone." (D287.3) The
    /// last-used sentence is left out when none of the payees has a category (D297.4).
    public var mergeFootnote: String {
        guard let survivorID, let survivor = listing.payee(survivorID) else {
            return CategoryText.mergingCantBeUndone
        }
        let ids = selectedPayees.map(\.id)
        let count = ids.reduce(0) { $0 + listing.uses(of: $1) }
        var sentences = [
            CategoryText.willUse(count: count, target: survivor.name),
            PayeeText.removed(selectedPayees.filter { $0.id != survivorID }.map(\.name)),
        ]
        if let category = listing.keptCategory(merging: ids, into: survivorID) {
            sentences.append(PayeeText.keepsCategory(payee: survivor.name, category: category.name))
        }
        sentences.append(CategoryText.mergingCantBeUndone)
        return CategoryText.sentences(sentences)
    }

    /// Merges the chosen payees into the survivor, all or nothing. Their transactions move to it and they're
    /// removed; the survivor keeps the most recent last-used category (D291.5). Not undoable, so this window's
    /// Undo and Redo history is cleared (D287.4).
    @discardableResult
    public func merge() -> Bool {
        guard let survivorID, canMerge else {
            return false
        }
        do {
            try useCases.manage.merge(selectedPayees.map(\.id), into: survivorID)
        } catch {
            load()
            alert = PayeeText.saveFailed
            return false
        }
        selection = []
        self.survivorID = nil
        didChange(removing: true)
        return true
    }

    // MARK: Rename

    /// A row's tap: opens its editor sheet.
    public func openEditor(for id: UUID) {
        editor = makeEditor(for: id)
    }

    public func makeEditor(for id: UUID) -> PayeeEditorViewModel? {
        guard let payee = listing.payee(id) else {
            return nil
        }
        return PayeeEditorViewModel(payee: payee, useCases: useCases, screen: self)
    }

    // MARK: Changes

    func didChange(removing: Bool) {
        if removing {
            onRemoval()
        }
        load()
        changed()
    }
}
