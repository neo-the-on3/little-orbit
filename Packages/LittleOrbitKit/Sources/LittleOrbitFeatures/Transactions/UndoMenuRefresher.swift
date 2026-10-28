import Foundation
import LittleOrbitCore

#if canImport(AppKit) && os(macOS)
    import AppKit
#endif

/// Keeps Edit › Undo and Redo current as each undo notification posts (B1 on #201, Tech Architect's n3). A ⌘Z typed
/// right after the first keystroke must find Undo already on: so each observer reads the items again on the posting
/// thread, synchronously, with no main-queue hop. The undo manager, and so its notifications, are the main thread's;
/// one posted off it, which nothing here does, is read on the main actor's next turn instead. `read` decides the
/// items, the batch gate's closed state winning (`UndoMenuItems(_:gateClosed:)`), and `changed` hears each new
/// value. AppKit-free but for `rebuildEditMenu`, so its timing is tested on Linux; on the Mac `FocusedUndoMenu` owns
/// one. `onMainThread` is `Thread.isMainThread`, the main actor's thread on the Mac; a Linux test's main actor runs
/// elsewhere, so it says.
///
/// After each read, `updateMenu` has the Edit menu rebuilt in the same call, with no hop (n2 on #201, Tech Architect's
/// spike (a)): Tester2 saw Edit › Undo stay disabled about 0.65 s after a batch's end although the items read on.
/// `NSMenu.update()`, tried first, left the lag and cost about 13 ms a refresh, so it asks the menu's delegate.
@MainActor
final class UndoMenuRefresher {
    /// The items as last read.
    private(set) var items: UndoMenuItems
    /// Hears each read that changed the items, in the same turn.
    var changed: @MainActor (UndoMenuItems) -> Void = { _ in }
    /// Has the Edit menu apply the items, after `changed`, at every refresh and before it returns: on the Mac, its
    /// delegate's `menuNeedsUpdate(_:)` (`rebuildEditMenu`); nothing elsewhere. Tests record it.
    var updateMenu: @MainActor () -> Void = UndoMenuRefresher.rebuildEditMenu
    /// Whether `updateMenu` is running, so a refresh it sets off reads but doesn't update the menu again.
    private var isUpdatingMenu = false
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

    /// Reads the items again now, tells `changed` if they changed, then has the menu bar apply them
    /// (`updateMenu`), all before it returns.
    @discardableResult
    func refresh() -> UndoMenuItems {
        let next = read()
        if next != items {
            items = next
            changed(next)
        }
        if !isUpdatingMenu {
            isUpdatingMenu = true
            #if DEBUG
                // Its cost, start to end, for Tester2 (n2).
                let span = BatchTrace.begin("ledger.editMenu.update")
            #endif
            updateMenu()
            #if DEBUG
                span.end()
            #endif
            isUpdatingMenu = false
        }
        return next
    }

    /// On the Mac, asks the Edit menu's delegate, SwiftUI's, to rebuild it now (`menuNeedsUpdate(_:)`), as AppKit
    /// does before it opens the menu, so Edit › Undo's `NSMenuItem` takes the items' enabled state without waiting
    /// for SwiftUI's next pass. The Edit menu is the main menu's submenu holding Undo: an item sending `undo:`, or
    /// ⌘Z, never its localized title. Only `menuNeedsUpdate(_:)`, not the delegate's `numberOfItems(in:)` or
    /// `menu(_:update:at:shouldCancel:)`, and no `NSMenu.update()`. Nothing elsewhere.
    static func rebuildEditMenu() {
        #if canImport(AppKit) && os(macOS)
            guard let mainMenu = NSApp?.mainMenu else {
                return
            }
            for item in mainMenu.items {
                guard let menu = item.submenu, menu.items.contains(where: isUndoItem) else {
                    continue
                }
                menu.delegate?.menuNeedsUpdate?(menu)
                return
            }
        #endif
    }

    #if canImport(AppKit) && os(macOS)
        /// Whether `item` is Edit › Undo: it sends `undo:`, or its key equivalent is ⌘Z (the app's SwiftUI item).
        private static func isUndoItem(_ item: NSMenuItem) -> Bool {
            item.action == UndoCommandGate.Command.undo.action
                || (item.keyEquivalent == "z" && item.keyEquivalentModifierMask == .command)
        }
    #endif

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
