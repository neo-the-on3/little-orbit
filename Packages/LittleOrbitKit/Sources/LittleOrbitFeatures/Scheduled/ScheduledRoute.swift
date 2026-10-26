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
