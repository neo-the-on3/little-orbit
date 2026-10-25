import Foundation
import LittleOrbitDomain
import Observation

/// The Mac Merge 2 Categories sheet (#24 design, Mac merge, survivor sheet): two selected categories of the
/// same kind, a Keep pop-up for the one that stays, and the footnote for the one merged into it. Only a
/// direction the ledger allows is offered: a parent with subcategories never goes under a subcategory, and a
/// category never merges into its own subcategory (D291.2). A refused merge shows D291.1's alert on this
/// sheet, which stays open. The choices are read once, when the sheet opens.
@MainActor
@Observable
public final class MetadataCategoryMerge: Identifiable {
    public let title: String
    public let message: String
    /// The categories that can be kept, in the table's order.
    public let keepOptions: [CategoryRow]
    /// The category that's kept; the other one is merged into it.
    public var keptID: UUID?
    /// The sheet's own alert (D291.1), so the window under it never shows the same one.
    public var alert: CategoryAlert?

    @ObservationIgnored private let ids: [UUID]
    @ObservationIgnored private weak var screen: CategoriesViewModel?

    /// `ids` are the two selected categories, in the table's order; `selectionOrder` is the order they were
    /// selected in, for a tie.
    init(ids: [UUID], selectionOrder: [UUID], screen: CategoriesViewModel) {
        self.ids = ids
        self.screen = screen
        let categories = ids.compactMap(screen.category)
        let kind = categories.first?.kind ?? .expense
        title = MetadataText.mergeTitle(ids.count)
        message = MetadataText.mergeMessage(
            categories.first?.name ?? "",
            categories.last?.name ?? "",
            kind: kind,
        )
        // The targets are read for the pair's kind; the Mac has no kind tab.
        screen.kind = kind
        keepOptions =
            categories.filter { kept in
                categories.filter { $0.id != kept.id }
                    .allSatisfy { source in screen.mergeTargets(for: source.id).contains { $0.id == kept.id } }
            }
            .map(screen.row)
        // The one more transactions use is kept, as the design shows; a tie keeps the one selected first (D304.5).
        let most = keepOptions.map { screen.listing.uses(of: $0.id) }.max()
        let mostUsed = Set(keepOptions.filter { screen.listing.uses(of: $0.id) == most }.map(\.id))
        keptID = selectionOrder.first(where: mostUsed.contains) ?? keepOptions.first { mostUsed.contains($0.id) }?.id
    }

    public nonisolated var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    /// The category merged into the kept one.
    public var sourceID: UUID? {
        guard let keptID else {
            return nil
        }
        return ids.first { $0 != keptID }
    }

    public var canMerge: Bool {
        sourceID != nil
    }

    /// "25 transactions will use Food & Dining. Groceries is then deleted. Merging can’t be undone.", with
    /// “Its subcategory moves to …” before the last sentence when the merged category has subcategories (D301).
    /// The Keep pop-up only lists the same kind, so iOS's “… aren’t listed” sentence isn't here. Budgets join it
    /// with #25 (D295.1).
    public var footnote: String {
        guard let screen, let sourceID, let keptID, let source = screen.category(sourceID),
            let kept = screen.category(keptID)
        else {
            return CategoryText.mergingCantBeUndone
        }
        var sentences = [
            CategoryText.willUse(count: screen.listing.uses(of: sourceID), target: kept.name),
            CategoryText.thenDeleted(source.name),
        ]
        let subcategoryCount = screen.listing.subcategories(of: sourceID).count
        if subcategoryCount > 0 {
            sentences.append(CategoryText.subcategoriesMove(count: subcategoryCount, to: kept.name))
        }
        sentences.append(CategoryText.mergingCantBeUndone)
        return CategoryText.sentences(sentences)
    }

    /// Merges, all or nothing. On failure the sheet keeps its alert and stays open.
    public func confirm() -> Bool {
        guard let screen, let sourceID, let keptID else {
            return false
        }
        if screen.merge(sourceID, into: keptID) {
            return true
        }
        alert = screen.alert
        screen.alert = nil
        return false
    }
}
