import Foundation

/// Where a Scheduled row goes: an item's own screen, or the Completed list.
public enum ScheduledRoute: Hashable, Sendable {
    case item(UUID)
    case completed
}

/// One window's Scheduled list model, for screens that a stack's root pushes over the list. On iPhone and iPad the
/// Accounts stack's typed path holds `AccountsRoute`, and only its root's destinations work, so the item and
/// Completed screens are built there and find the list's model here (Tester's #198 iOS FAIL).
///
/// It holds the model weakly. The list's own state still owns it, so the model lives exactly as long as the list is
/// on the stack, as on the Mac, and the next visit starts with a new one (D338.6).
@MainActor
final class ScheduledListSlot {
    private(set) weak var model: ScheduledListViewModel?

    init() {}

    /// The list on the stack calls this when it appears, before any of its links can be followed.
    func attach(_ model: ScheduledListViewModel) {
        self.model = model
    }
}

/// Who builds the screens a Scheduled list opens. A list on someone else's stack always gets both the slot and the
/// way to push onto that stack, so no button there can fall back to a navigation link (which adds a row chevron on
/// iPhone; Tech Architect 5647157983).
@MainActor
enum ScheduledListHost<Link: Hashable> {
    /// The list registers its own destinations (the Mac's detail column stack).
    case ownStack
    /// A stack whose root registers the destinations for the list's link values and builds them with the model in
    /// `slot`; `open` pushes a link value onto it, for buttons such as the watch card's View Item (the iPhone and
    /// iPad Accounts stack).
    case parentStack(slot: ScheduledListSlot, open: (Link) -> Void)

    /// The slot the pushed screens read the list's model from; `nil` on the list's own stack.
    var slot: ScheduledListSlot? {
        switch self {
        case .ownStack: nil
        case .parentStack(let slot, _): slot
        }
    }

    /// Pushes onto the parent stack; `nil` exactly when there's no slot.
    var openLink: ((Link) -> Void)? {
        switch self {
        case .ownStack: nil
        case .parentStack(_, let open): open
        }
    }
}
