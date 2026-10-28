import Foundation

/// Whether a key-down for ⌘Z or ⇧⌘Z came to one of the app's own windows while it's key, for
/// `UndoKeyPolicy.Input.isAppKeyWindow` (n2 on #201; Tech Architect on Tester2's 6473659858).
///
/// While the event's window still exists, one of `NSApp.windows`, the rule is unchanged from before: that window
/// must be key. Only when the event names no window, or one the app no longer lists, does it fall back to the
/// app's key window as the key-down arrives: a ⌘Z queued while a save blocked the main thread, whose batch
/// progress sheet closed before it was handled, is judged against the window that is key now, so it reaches the
/// gate's `gateClosed` or `cannotRun` instead of reading as `notKeyWindow`. That key window must be the app's: one
/// it lists, or a sheet or alert attached, up to `maxChain` windows, to one it lists. Another app's window, a
/// system panel, or no key window fails. Platform-neutral over any window type, so it's tested on Linux;
/// `UndoKeyMonitor` passes `NSWindow`s.
enum UndoKeyWindowPolicy {
    /// How many windows the fallback's ownership check looks at: the key window and its sheet parents.
    static let maxChain = 8

    /// `appWindows` is `NSApp.windows`; `isKey` a window's `isKeyWindow`; `parent` a window's `sheetParent`, else
    /// its `parent`.
    static func isAppKeyWindow<Window: AnyObject>(
        eventWindow: Window?,
        keyWindow: Window?,
        appWindows: [Window],
        isKey: (Window) -> Bool,
        parent: (Window) -> Window?,
    ) -> Bool {
        if let eventWindow, appWindows.contains(where: { $0 === eventWindow }) {
            return isKey(eventWindow)
        }
        guard let keyWindow else {
            return false
        }
        return owned(keyWindow, appWindows, parent)
    }

    /// Whether `window`, or a window it's attached to within `maxChain` windows, is one the app lists.
    private static func owned<Window: AnyObject>(
        _ window: Window,
        _ appWindows: [Window],
        _ parent: (Window) -> Window?,
    ) -> Bool {
        var next: Window? = window
        var looked = 0
        while let current = next, looked < maxChain {
            if appWindows.contains(where: { $0 === current }) {
                return true
            }
            next = parent(current)
            looked += 1
        }
        return false
    }
}
