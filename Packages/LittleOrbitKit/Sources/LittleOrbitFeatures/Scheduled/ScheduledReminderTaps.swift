import Foundation
import LittleOrbitDomain
import Observation

/// One tap on a reminder: the item it's about, by ID (S33). Each tap is its own value, so tapping the same item's
/// reminder twice opens it twice.
public struct ScheduledReminderTap: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let itemID: UUID
    /// The window that opens it: on iPad the scene the system sent the tap to, on the Mac the main window brought
    /// to the front (Tech Architect NB2). `nil` lets the first window up take it, as on a cold launch.
    public fileprivate(set) var window: String?

    public init(itemID: UUID, window: String? = nil, id: UUID = UUID()) {
        self.id = id
        self.itemID = itemID
        self.window = window
    }
}

/// Reminder taps waiting for a window to open them (#26 S33, D353.3, D354.2). The App's notification delegate
/// reports each tap here, even before any window is up, as on a cold launch; the tap waits until a window's
/// navigation takes it. Only the window it's for takes it, and only the latest one waits.
@MainActor
@Observable
public final class ScheduledReminderTaps {
    public private(set) var pending: ScheduledReminderTap?
    /// The main windows that are up, oldest first, by the identifier each reports.
    public private(set) var windows: [String] = []

    public init() {}

    /// A reminder for `itemID` was tapped, for `window` to open, or any window when it's `nil`.
    public func tapped(itemID: UUID, window: String? = nil) {
        pending = ScheduledReminderTap(itemID: itemID, window: window)
    }

    /// The waiting tap, once, if it's for `window`: the next call returns `nil` until another tap.
    public func take(for window: String?) -> ScheduledReminderTap? {
        guard let pending, pending.window == nil || pending.window == window else {
            return nil
        }
        self.pending = nil
        return pending
    }

    /// A main window is up and reports `window` as its identifier.
    public func windowAppeared(_ window: String) {
        if !windows.contains(window) {
            windows.append(window)
        }
    }

    /// A main window closed. A tap still waiting for it goes to whichever window takes it next.
    public func windowClosed(_ window: String) {
        windows.removeAll { $0 == window }
        if pending?.window == window {
            pending?.window = nil
        }
    }
}

/// Where a window's navigation goes for a tapped reminder (S33, UI Designer 6402418696).
public enum ScheduledReminderRouting {
    /// The iOS navigation stack after a tap: Scheduled, then the item on top, pushed as typed routes the way the
    /// list's rows push them, so the path is always the whole stack and a later tap sees an item a reminder opened
    /// (Tech Architect 5660914450 B1). With its sheets closed it's just Scheduled and the item. A sheet with unsaved
    /// edits stays open, so the screen that shows it stays on the stack and the item goes on top of it, once: on a
    /// stack that already starts with Scheduled, unless it's already the top screen; otherwise after Scheduled.
    /// `item` is read fresh (D354.2): `nil` for a deleted item opens the list, or leaves a Scheduled stack as it is.
    public static func path<Route: Equatable>(
        _ path: [Route],
        scheduled: Route,
        item: Route?,
        sheets: SheetNavigation,
    ) -> [Route] {
        let opened = item.map { [$0] } ?? []
        switch sheets {
        case .afterClosing:
            return [scheduled] + opened
        case .underneath where path.first == scheduled:
            guard let item, path.last != item else {
                return path
            }
            return path + [item]
        case .underneath:
            return path + [scheduled] + opened
        }
    }

    /// The Mac Scheduled stack's path after a tap, set with the sidebar selection in one update, so the stack is
    /// built with the item already on it and nothing waits for the list (Tester 6419979176). With its sheets closed
    /// it's just the item. A sheet with unsaved edits stays open, so the screens under it stay and the item goes
    /// on top (UI Designer 6402418696). `item` is `nil` for a deleted item: the list, with no alert (D354.2).
    public static func macPath(
        _ path: [ScheduledRoute],
        item: UUID?,
        sheets: SheetNavigation,
    ) -> [ScheduledRoute] {
        switch (item, sheets) {
        case (nil, .afterClosing):
            []
        case (nil, .underneath):
            path
        case (let item?, .afterClosing):
            [.item(item)]
        case (let item?, .underneath):
            path.last == .item(item) ? path : path + [.item(item)]
        }
    }

    /// One of the Mac's main windows, as AppKit sees it.
    public struct MacWindow: Equatable, Sendable {
        public let id: String
        public let isKey: Bool
        public let isMiniaturized: Bool
        /// Its place front to back among the windows on screen; `nil` when it's minimised.
        public let order: Int?

        public init(id: String, isKey: Bool, isMiniaturized: Bool, order: Int?) {
            self.id = id
            self.isKey = isKey
            self.isMiniaturized = isMiniaturized
            self.order = order
        }
    }

    /// The Mac main window a tap opens in (UI Designer 6402418696, Tech Architect NB2): the key one, else the
    /// frontmost on screen, else a minimised one to bring back. `nil` when no main window is open, so the App opens
    /// a new one. Settings isn't a main window, so it stays behind.
    public static func macWindow(_ windows: [MacWindow]) -> MacWindow? {
        if let key = windows.first(where: { $0.isKey && !$0.isMiniaturized }) {
            return key
        }
        let onScreen = windows.filter { !$0.isMiniaturized && $0.order != nil }
        if let front = onScreen.min(by: { ($0.order ?? .max) < ($1.order ?? .max) }) {
            return front
        }
        return windows.first { $0.isMiniaturized }
    }
}

extension ScheduledFeature {
    /// The item a tapped reminder opens, read fresh (D354.2): `nil` when it was deleted, or the store can't be read.
    public func itemOpened(by tap: ScheduledReminderTap) -> UUID? {
        (try? useCases.load.listing())?.item(tap.itemID) == nil ? nil : tap.itemID
    }
}

extension ScheduledListViewModel {
    /// A Scheduled screen that stays on the stack now shows `new` instead of `old`. A Mac clean-sheet tap on another
    /// item's screen replaces that item on the path ([Phone Plan] to [Electricity]), and the stack keeps the screen
    /// and only changes its item, so it never reports Phone Plan going or Electricity coming. Phone Plan then stayed
    /// on top of `visibleScreens` and kept presenting after Back, so + Add and the list's Edit… opened nothing
    /// (Tester2 6425404539).
    public func screenChanged(from old: ScheduledScreen, to new: ScheduledScreen) {
        guard old != new else {
            return
        }
        screenDisappeared(old)
        screenAppeared(new)
    }
}
