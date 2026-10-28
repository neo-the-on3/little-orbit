import Testing

@testable import LittleOrbitFeatures

/// The key-down monitor's window check (Tech Architect on Tester2's 6473659858): while the event's window is still
/// one the app lists, it must be key, as before; only a key-down whose window has gone is judged against the app's
/// key window now, which must be the app's. Mutants: requiring the main window fails `mainIsKey` and `sheetIsKey`;
/// dropping the ownership check fails `notTheApps`; the event's window only fails `goneSheet`; always using the
/// key window fails `eventWindowNotKey`; a longer chain fails `chainCap`.
@Suite("Key-down monitor: the app's own key window, sheets included (n2)")
struct UndoKeyWindowPolicyTests {
    final class Window {
        let name: String
        var sheetParent: Window?
        init(_ name: String, sheetParent: Window? = nil) {
            self.name = name
            self.sheetParent = sheetParent
        }
    }

    let main = Window("main")
    let other = Window("other")
    let panel = Window("system panel")

    /// `key` is the app's key window, and the only window whose `isKeyWindow` is true.
    private func check(event: Window?, key: Window?, app: [Window]) -> Bool {
        UndoKeyWindowPolicy.isAppKeyWindow(
            eventWindow: event,
            keyWindow: key,
            appWindows: app,
            isKey: { $0 === key },
            parent: \.sheetParent,
        )
    }

    @Test("The key window is the main window: passes")
    func mainIsKey() {
        #expect(check(event: main, key: main, app: [main, other]))
        #expect(check(event: other, key: other, app: [main, other]), "Any of the app's windows, not only main")
    }

    @Test("The key window is the batch's progress sheet, or an alert, attached to the main window: passes")
    func sheetIsKey() {
        let sheet = Window("progress sheet", sheetParent: main)
        #expect(check(event: sheet, key: sheet, app: [main, sheet]))
        #expect(check(event: sheet, key: sheet, app: [main]), "Owned through its sheetParent when not listed")
        let alert = Window("Discard Changes?", sheetParent: sheet)
        #expect(check(event: alert, key: alert, app: [main]), "Up the chain")
    }

    @Test("A queued key-down whose sheet has gone: judged against the key window now, the main window: passes")
    func goneSheet() {
        #expect(check(event: nil, key: main, app: [main]), "No event window")
        let closed = Window("closed progress sheet", sheetParent: main)
        #expect(check(event: closed, key: main, app: [main]), "The event's sheet is no longer listed")
    }

    @Test("The event's window still exists and is the app's but isn't key, another app window is: fails, as before")
    func eventWindowNotKey() {
        #expect(!check(event: main, key: other, app: [main, other]))
        let sheet = Window("progress sheet", sheetParent: main)
        #expect(!check(event: sheet, key: main, app: [main, sheet]), "A listed sheet that's no longer key")
    }

    @Test("The key window isn't the app's, or there's none: fails")
    func notTheApps() {
        #expect(!check(event: panel, key: panel, app: [main]))
        #expect(!check(event: nil, key: panel, app: [main]))
        #expect(!check(event: main, key: panel, app: [main]), "Another app's or a system panel is key")
        #expect(!check(event: nil, key: nil, app: [main]))
        #expect(!check(event: main, key: nil, app: [main]), "No key window: the app isn't active")
        let foreign = Window("foreign sheet", sheetParent: panel)
        #expect(!check(event: foreign, key: foreign, app: [main]))
    }

    @Test("A sheet chain longer than the cap reads as not the app's: fails; a cycle ends there too")
    func chainCap() {
        var top = main
        var chain: [Window] = []
        for level in 1...UndoKeyWindowPolicy.maxChain {
            top = Window("sheet \(level)", sheetParent: top)
            chain.append(top)
        }
        #expect(check(event: nil, key: chain[UndoKeyWindowPolicy.maxChain - 2], app: [main]), "Main at the cap")
        #expect(!check(event: nil, key: chain[UndoKeyWindowPolicy.maxChain - 1], app: [main]), "Main past the cap")
        let first = Window("loop 1")
        let second = Window("loop 2", sheetParent: first)
        first.sheetParent = second
        #expect(!check(event: nil, key: first, app: [main]))
    }
}
