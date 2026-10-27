#if canImport(AppKit) && os(macOS)
    import AppKit
    import Testing

    @testable import LittleOrbitFeatures

    /// D388.5 on the Mac (B3): the discard alert's keys are set by hand, Esc on Keep Editing and none on Discard
    /// Changes, because a SwiftUI alert gave Esc to Discard Changes. Linux has no AppKit and skips this suite.
    @MainActor
    @Suite("Mac discard alert: Esc keeps editing, no key discards (D388.5, B3)")
    struct DiscardAlertBridgeTests {
        let alert = makeDiscardAlert(
            title: "Discard Changes?",
            message: "Your changes to Rent won’t be saved.",
            keepEditing: "Keep Editing",
            discard: "Discard Changes",
        )

        @Test("Keep Editing first with Esc, Discard Changes second with no key, and no button has Return")
        func buttons() throws {
            let buttons = alert.buttons
            try #require(buttons.count == 2)
            #expect(buttons.map(\.title) == ["Keep Editing", "Discard Changes"])
            #expect(buttons[0].keyEquivalent == "\u{1b}")
            #expect(buttons[1].keyEquivalent.isEmpty)
            #expect(!buttons.contains { $0.keyEquivalent == "\r" })
            #expect(!buttons[1].hasDestructiveAction)
        }

        @Test("The title and message come from the catalog strings passed in; no message leaves it empty")
        func text() {
            #expect(alert.messageText == "Discard Changes?")
            #expect(alert.informativeText == "Your changes to Rent won’t be saved.")
            #expect(alert.alertStyle == .warning)
            let bare = makeDiscardAlert(title: "Discard Changes?", message: nil, keepEditing: "K", discard: "D")
            #expect(bare.informativeText.isEmpty)
        }

        @Test("Only the second button discards; Keep Editing, which Esc clicks, and any other ending keep the edits")
        func responses() {
            #expect(discardAlertDiscards(.alertSecondButtonReturn))
            #expect(!discardAlertDiscards(.alertFirstButtonReturn))
            #expect(!discardAlertDiscards(.cancel))
            #expect(!discardAlertDiscards(.abort))
        }
    }
#endif
