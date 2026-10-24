#if canImport(SwiftUI) && (os(macOS) || os(iOS))
    import SwiftUI

    /// What a menu command does for the focused window's one selected row: Duplicate or Refund… (D65, #31).
    public struct SelectionAction {
        let perform: @MainActor () -> Void

        init(_ perform: @escaping @MainActor () -> Void) {
            self.perform = perform
        }
    }

    /// Edit > Duplicate for the focused window's selection: available on one row, or hidden while the one
    /// selected row is a refund (UI Designer, 23 Oct).
    public enum DuplicateCommand {
        case available(SelectionAction)
        case hidden
    }

    extension FocusedValues {
        /// Set by an account's history for its selection; `nil` (no row, or several) disables ⌘D.
        @Entry public var duplicateSelection: DuplicateCommand?
        /// Set by an account's history while exactly one expense is selected; `nil` disables ⌘R.
        @Entry public var refundSelection: SelectionAction?
    }

    /// The menu commands for transactions, on macOS and on iPad with a hardware keyboard (S40, S43, S44), in a
    /// group of their own after the pasteboard group (UI Designer, 23 Oct): Duplicate (⌘D) copies the one
    /// selected row, and Refund… (⌘R) opens the refund sheet for the one selected expense. Each is disabled
    /// for several rows or none. Refund… is disabled on a row it isn't offered on, and Duplicate isn't shown
    /// while a refund is selected (D65; UI Designer, 23 Oct).
    public struct TransactionCommands: Commands {
        @FocusedValue(\.duplicateSelection) private var duplicate
        @FocusedValue(\.refundSelection) private var refund

        public init() {}

        public var body: some Commands {
            CommandGroup(after: .pasteboard) {
                switch duplicate {
                case .available(let action):
                    Button("Duplicate") { action.perform() }
                        .keyboardShortcut("d", modifiers: .command)
                case .hidden:
                    EmptyView()
                case nil:
                    Button("Duplicate") {}
                        .keyboardShortcut("d", modifiers: .command)
                        .disabled(true)
                }
                Button("Refund…") { refund?.perform() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(refund == nil)
            }
        }
    }
#endif
