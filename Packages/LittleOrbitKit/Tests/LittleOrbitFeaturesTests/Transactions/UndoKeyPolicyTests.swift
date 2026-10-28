import Foundation
import Testing

@testable import LittleOrbitFeatures

/// n2 on #201 (Tech Architect's option (d)): when the key-down monitor runs ⌘Z or ⇧⌘Z itself, over the whole truth
/// table. Mutants: always acting, never acting, ignoring `gateClosed`, ignoring the item's enabled state (a double
/// Undo) and ignoring ⇧ (Redo run as Undo) each fail `truthTable`; the named rows fail with them.
@Suite("Key-down monitor: ⌘Z or ⇧⌘Z run only while its item lags (n2)")
struct UndoKeyPolicyTests {
    typealias Policy = UndoKeyPolicy

    /// ⌘Z, with Undo's item still disabled just after a batch: every other input as when the monitor acts.
    static func lagging(_ command: UndoCommandGate.Command = .undo) -> Policy.Input {
        Policy.Input(
            characters: command == .undo ? "z" : "Z",
            modifiers: command == .undo ? [.command] : [.command, .shift],
            isAppKeyWindow: true,
            isMenuTracking: false,
            gateClosed: false,
            canUndo: true,
            canRedo: true,
            undoItemEnabled: false,
            redoItemEnabled: false,
        )
    }

    @Test("Every combination: acts only with the key exact, the app's key window, no menu, gate open, can, item off")
    func truthTable() {
        let keys: [Key] = [
            Key("z", [.command], .undo),
            Key("Z", [.command, .shift], .redo),
            Key("z", [.command, .shift], .redo),
            Key("z", [], nil),
            Key("z", [.command, .option], nil),
            Key("z", [.command, .control], nil),
            Key("Z", [.command, .shift, .option], nil),
            Key("z", [.command, .function], nil),
            Key("z", [.command, .other], nil),
            Key("y", [.command], nil),
            Key(nil, [.command], nil),
        ]
        var acted = 0
        for key in keys {
            let (characters, modifiers, command) = (key.characters, key.modifiers, key.command)
            for bits in 0..<(1 << 7) {
                let bit = { (index: Int) in bits & (1 << index) != 0 }
                let input = Policy.Input(
                    characters: characters,
                    modifiers: modifiers,
                    isAppKeyWindow: bit(0),
                    isMenuTracking: bit(1),
                    gateClosed: bit(2),
                    canUndo: bit(3),
                    canRedo: bit(4),
                    undoItemEnabled: bit(5),
                    redoItemEnabled: bit(6),
                )
                let expected: Policy.Decision
                if let command, input.isAppKeyWindow, !input.isMenuTracking, !input.gateClosed,
                    command == .undo ? input.canUndo && !bit(5) : input.canRedo && !bit(6)
                {
                    expected = .act(command)
                    acted += 1
                } else {
                    expected = .pass
                }
                #expect(Policy.decide(input) == expected, "\(String(describing: characters)) \(modifiers) \(bits)")
                #expect((Policy.reason(input) == .act) == (expected != .pass), "The signposted reason agrees")
            }
        }
        // ⌘Z, and ⇧⌘Z as "Z" and as "z": five inputs fixed, the other command's two free, so 4 each act.
        #expect(acted == 12)
    }

    /// A key-down's characters and modifiers, and the command it is, if any.
    struct Key {
        var characters: String?
        var modifiers: Policy.Modifiers
        var command: UndoCommandGate.Command?

        init(_ characters: String?, _ modifiers: Policy.Modifiers, _ command: UndoCommandGate.Command?) {
            self.characters = characters
            self.modifiers = modifiers
            self.command = command
        }
    }

    @Test("The lag after a batch: Undo's item off, gate open, can undo: acts, so ⌘Z reaches the gate")
    func lagActs() {
        #expect(Policy.decide(Self.lagging(.undo)) == .act(.undo))
        #expect(Policy.decide(Self.lagging(.redo)) == .act(.redo), "⇧⌘Z is Redo, never Undo")
    }

    @Test("Item already on: passes, so AppKit's own menu path runs it once, never twice")
    func enabledItemPasses() {
        var input = Self.lagging()
        input.undoItemEnabled = true
        #expect(Policy.decide(input) == .pass)
        input.undoItemEnabled = nil
        #expect(Policy.decide(input) == .pass, "No item found: never acts")
    }

    @Test("Gate closed (a batch running, or a menu holding it): passes, so the disabled item beeps (D407.1)")
    func closedGatePasses() {
        var input = Self.lagging()
        input.gateClosed = true
        #expect(Policy.decide(input) == .pass)
    }

    @Test("A text field being edited: canUndo is the field's typing, so it acts and undo: reaches the field first")
    func textFieldFirstResponder() {
        // The field editor's undo manager can undo its typing; Undo's item hasn't caught up.
        var input = Self.lagging()
        input.canRedo = false
        #expect(Policy.decide(input) == .act(.undo))
        // Nothing typed and nothing to undo: passes, and AppKit beeps as before.
        input.canUndo = false
        #expect(Policy.decide(input) == .pass)
    }

    @Test("Menu tracking, another window or no window: passes")
    func elsewherePasses() {
        var input = Self.lagging()
        input.isMenuTracking = true
        #expect(Policy.decide(input) == .pass)
        input = Self.lagging()
        input.isAppKeyWindow = false
        #expect(Policy.decide(input) == .pass)
    }

    @Test("ledger.keyMonitor.pass names the first thing that stops it, in order, and act when nothing does")
    func reasons() {
        func with(_ change: (inout Policy.Input) -> Void, _ command: UndoCommandGate.Command = .undo) -> Policy.Reason {
            var input = Self.lagging(command)
            change(&input)
            return Policy.reason(input)
        }
        #expect(with({ _ in }) == .act)
        #expect(with({ _ in }, .redo) == .act)
        #expect(with { $0.characters = "y" } == .notZ)
        #expect(with { $0.characters = nil } == .notZ)
        #expect(with { $0.modifiers = [.command, .option] } == .flagsMismatch)
        #expect(with { $0.modifiers = [] } == .flagsMismatch)
        #expect(with { $0.isAppKeyWindow = false } == .notKeyWindow)
        #expect(with { $0.isMenuTracking = true } == .tracking)
        #expect(with { $0.gateClosed = true } == .gateClosed)
        #expect(with { $0.canUndo = false } == .cannotRun)
        #expect(with({ $0.canRedo = false }, .redo) == .cannotRun)
        #expect(with { $0.undoItemEnabled = nil } == .noItem)
        #expect(with { $0.undoItemEnabled = true } == .itemEnabled)
        #expect(with({ $0.redoItemEnabled = true }, .redo) == .itemEnabled)
        #expect(with({ $0.undoItemEnabled = true }, .redo) == .act, "Redo reads Redo's item, not Undo's")
        // The earliest stop wins: not key and gate closed reads notKeyWindow.
        #expect(
            with {
                $0.isAppKeyWindow = false
                $0.gateClosed = true
            } == .notKeyWindow
        )
        for reason in Policy.Reason.allCases {
            #expect(reason.tag.description == reason.rawValue, "The signpost's tag is the case's name")
        }
    }
}
