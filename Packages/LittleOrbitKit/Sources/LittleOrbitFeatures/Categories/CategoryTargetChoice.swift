import Foundation
import LittleOrbitDomain
import Observation

/// The Merge “Groceries” into… or Move To sheet (#24 design, merge and move target). Its rows are read from
/// the store once, when the sheet opens, and kept, so re-rendering or choosing a row reads nothing
/// (Tech Architect's B1 on #155). The header and footnote come from the screen's loaded tree.
@MainActor
@Observable
public final class CategoryTargetChoice: Identifiable {
    public enum Purpose: Hashable, Sendable {
        case merge(UUID)
        case move(UUID)
    }

    public let purpose: Purpose
    /// The same-kind categories offered, in tree order (D291.4).
    public let rows: [CategoryRow]
    public let title: String
    public let header: String
    public var targetID: UUID?
    /// The sheet's own alert, so the screen under it never shows the same one (D291.1).
    public var alert: CategoryAlert?

    @ObservationIgnored private weak var screen: CategoriesViewModel?

    init(purpose: Purpose, screen: CategoriesViewModel) {
        self.purpose = purpose
        self.screen = screen
        switch purpose {
        case .merge(let id):
            rows = screen.mergeTargets(for: id)
            title = CategoryText.mergeTitle(screen.category(id)?.name ?? "")
            header = screen.mergeHeader(for: id)
        case .move(let id):
            rows = screen.moveTargets(forDeleting: id)
            title = CategoryText.moveToTitle
            header = screen.moveHeader(forDeleting: id)
        }
    }

    public nonisolated var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    public var isMerge: Bool {
        if case .merge = purpose {
            return true
        }
        return false
    }

    public var categoryID: UUID {
        switch purpose {
        case .merge(let id), .move(let id): id
        }
    }

    /// The Merge footnote names the chosen target; the Move To footer doesn't change.
    public var footer: String {
        guard let screen else {
            return ""
        }
        return isMerge
            ? screen.mergeFootnote(for: categoryID, into: targetID)
            : screen.moveFooter(forDeleting: categoryID)
    }

    /// Merges or moves into the chosen target. On failure the sheet keeps its alert and stays open.
    public func confirm() -> Bool {
        guard let targetID, let screen else {
            return false
        }
        let done = isMerge ? screen.merge(categoryID, into: targetID) : screen.delete(categoryID, movingTo: targetID)
        if !done {
            alert = screen.alert
            screen.alert = nil
        }
        return done
    }
}
