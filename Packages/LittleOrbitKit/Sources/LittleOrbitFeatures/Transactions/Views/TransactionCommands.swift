#if canImport(SwiftUI) && os(macOS)
    import SwiftUI

    /// What Edit > Refund… does for the focused window: refund its one selected expense (D65, #31).
    public struct RefundSelectionAction {
        let perform: @MainActor () -> Void

        init(_ perform: @escaping @MainActor () -> Void) {
            self.perform = perform
        }
    }

    extension FocusedValues {
        /// Set by an account's history while exactly one expense is selected; `nil` disables ⌘R.
        @Entry public var refundSelection: RefundSelectionAction?
    }

    /// The macOS menu commands for transactions: Edit > Refund… (⌘R) opens the refund sheet for the one
    /// selected expense, and is disabled for several rows, none, or a row Refund isn't offered on (D65, S44).
    public struct TransactionCommands: Commands {
        @FocusedValue(\.refundSelection) private var refund

        public init() {}

        public var body: some Commands {
            // A group of its own after the pasteboard group (UI Designer, 23 Oct).
            CommandGroup(after: .pasteboard) {
                Button("Refund…") { refund?.perform() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(refund == nil)
            }
        }
    }
#endif
