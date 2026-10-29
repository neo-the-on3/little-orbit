import Foundation

/// The automatic items catch-up leaves alone for now (D447): while a form save's
/// notice says one of an item's payments is back on its scheduled day, catch-up records nothing for that item, so
/// the notice's Undo still puts the move back exactly, with no record. The notice's OK, Undo or closing ends the
/// hold, and so does its list going away; the next catch-up then records the item as usual. One per launch, shared
/// by every window's list, like the catch-up hint's notices.
@MainActor
public final class ScheduledCatchUpHolds {
    private struct Hold {
        let itemID: UUID
        /// The list showing the notice. A hold whose list is gone is over, so a closed window never holds an item.
        weak var owner: AnyObject?
    }

    private var holds: [UUID: Hold] = [:]
    /// A normal catch-up, for the notice's OK. The feature sets it.
    var catchUp: () -> Void = {}

    public init() {}

    /// The items to hold now.
    var itemIDs: Set<UUID> {
        Set(holds.values.filter { $0.owner != nil }.map(\.itemID))
    }

    func hold(_ itemID: UUID, for noticeID: UUID, by owner: AnyObject) {
        holds = holds.filter { $0.value.owner != nil }
        holds[noticeID] = Hold(itemID: itemID, owner: owner)
    }

    func release(_ noticeID: UUID) {
        holds[noticeID] = nil
    }
}
