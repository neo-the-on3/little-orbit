import Foundation

/// Keeps Edit › Undo and Redo current as each undo notification posts (B1 on #201, Tech Architect's n3). A ⌘Z typed
/// right after the first keystroke must find Undo already on: so each observer reads the items again on the posting
/// thread, synchronously, with no main-queue hop. The undo manager, and so its notifications, are the main thread's;
/// one posted off it, which nothing here does, is read on the main actor's next turn instead. `read` decides the
/// items, the batch gate's closed state winning (`UndoMenuItems(_:gateClosed:)`), and `changed` hears each new
/// value. AppKit-free, so its timing is tested on Linux; on the Mac `FocusedUndoMenu` owns one. `onMainThread` is
/// `Thread.isMainThread`, the main actor's thread on the Mac; a Linux test's main actor runs elsewhere, so it says.
@MainActor
final class UndoMenuRefresher {
    /// The items as last read.
    private(set) var items: UndoMenuItems
    /// Hears each read that changed the items, in the same turn.
    var changed: @MainActor (UndoMenuItems) -> Void = { _ in }
    private let read: @MainActor () -> UndoMenuItems
    private var tokens: [any NSObjectProtocol] = []
    private let center: NotificationCenter

    init(
        center: NotificationCenter = .default,
        names: [Notification.Name],
        onMainThread: @escaping @Sendable () -> Bool = { Thread.isMainThread },
        read: @escaping @MainActor () -> UndoMenuItems,
    ) {
        self.center = center
        self.read = read
        items = read()
        tokens = names.map { name in
            // `queue: nil`: the block runs on the posting thread, before `post` returns.
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Self.onMain(onMainThread()) { self?.refresh() }
            }
        }
    }

    isolated deinit {
        for token in tokens {
            center.removeObserver(token)
        }
    }

    /// Reads the items again now, and tells `changed` if they changed.
    @discardableResult
    func refresh() -> UndoMenuItems {
        let next = read()
        if next != items {
            items = next
            changed(next)
        }
        return next
    }

    /// `body` at once on the main thread, as every undo notification posts; from any other thread, on the main
    /// actor's next turn.
    private nonisolated static func onMain(_ isMain: Bool, _ body: @escaping @MainActor @Sendable () -> Void) {
        if isMain {
            MainActor.assumeIsolated(body)
        } else {
            Task { @MainActor in body() }
        }
    }
}
