import Foundation

/// Where a Scheduled row goes: an item's own screen, or the Completed list.
public enum ScheduledRoute: Hashable, Sendable {
    case item(UUID)
    case completed
}

/// One window's Scheduled list model, for the list and the screens a stack's root pushes over it. On iPhone and iPad
/// the Accounts stack's typed path holds `AccountsRoute`, and only its root's destinations work, so the item and
/// Completed screens are built there and take the model from here (Tester's #198 iOS FAIL).
///
/// The slot makes the model when the stack gains its first Scheduled route and holds it, so the list and every screen
/// over it share one model whatever order SwiftUI builds them in, as when a reminder tap sets Scheduled and its item in
/// one update (Tech Architect 5661012630 B2). It lets the model go once no Scheduled screen is left on the stack, so
/// the next visit starts with a new one (D338.6).
@MainActor
final class ScheduledListSlot {
    private(set) var model: ScheduledListViewModel?

    init() {}

    /// This stack's model. `onStack` is whether the stack's path holds a Scheduled route as the screen is built: then
    /// it's the model already made, or `make()`'s, kept from now on. Without one, as when SwiftUI runs a popping
    /// screen's init again after the model went, it's the kept model if there still is one, else a throwaway that
    /// isn't kept, so no unused model is left for the next visit (D338.6, Tech Architect 5661097037 NB2).
    func model(onStack: Bool, or make: () -> ScheduledListViewModel) -> ScheduledListViewModel {
        if let model {
            return model
        }
        let made = make()
        if onStack {
            model = made
        }
        return made
    }

    /// The stack changed: with no Scheduled screen left on it, the model goes.
    func stackChanged(showsScheduled: Bool) {
        if !showsScheduled {
            model = nil
        }
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
    /// iPad Accounts stack). `onStack` is whether that stack's path holds a Scheduled route as the list is built.
    case parentStack(slot: ScheduledListSlot, onStack: Bool, open: (Link) -> Void)

    /// The slot the pushed screens read the list's model from; `nil` on the list's own stack.
    var slot: ScheduledListSlot? {
        switch self {
        case .ownStack: nil
        case .parentStack(let slot, _, _): slot
        }
    }

    /// The list's model: on a parent stack, the stack's one model from the slot (B2, NB2); otherwise its own.
    func model(or make: () -> ScheduledListViewModel) -> ScheduledListViewModel {
        switch self {
        case .ownStack: make()
        case .parentStack(let slot, let onStack, _): slot.model(onStack: onStack, or: make)
        }
    }

    /// Pushes onto the parent stack; `nil` exactly when there's no slot.
    var openLink: ((Link) -> Void)? {
        switch self {
        case .ownStack: nil
        case .parentStack(_, _, let open): open
        }
    }
}
