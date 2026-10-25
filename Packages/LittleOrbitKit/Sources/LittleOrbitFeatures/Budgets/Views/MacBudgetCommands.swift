#if canImport(SwiftUI) && os(macOS)
    import SwiftUI

    /// What the Budget menu can do in the front window right now (#25 part 5), published by the Mac Budgets
    /// screen. A `nil` action shows its item dimmed and drops its shortcut, so ⌘E or ⌘⌫ do their usual work
    /// elsewhere, and while a sheet or an alert is up.
    struct BudgetMenuActions {
        var newBudget: (@MainActor () -> Void)?
        var open: (@MainActor () -> Void)?
        var edit: (@MainActor () -> Void)?
        var changeLimit: (@MainActor () -> Void)?
        var duplicate: (@MainActor () -> Void)?
        var showPrevious: (@MainActor () -> Void)?
        var showNext: (@MainActor () -> Void)?
        var showCurrent: (@MainActor () -> Void)?
        var delete: (@MainActor () -> Void)?
    }

    private struct BudgetMenuKey: FocusedValueKey {
        typealias Value = BudgetMenuActions
    }

    extension FocusedValues {
        var budgetMenu: BudgetMenuActions? {
            get { self[BudgetMenuKey.self] }
            set { self[BudgetMenuKey.self] = newValue }
        }
    }

    /// The Mac's Budget menu (#25 part 5): the same commands as a budget's right-click menu, for the budget
    /// picked in the list or on show, with its shortcuts.
    public struct BudgetCommands: Commands {
        @FocusedValue(\.budgetMenu) private var actions

        public init() {}

        public var body: some Commands {
            CommandMenu(BudgetText.budgetMenu) {
                // ⌥⌘N: ⌘N stays New Window. Show Current Period has none, as ⌘T is Show Fonts and New Tab.
                item(
                    BudgetText.newBudgetEllipsis,
                    actions?.newBudget,
                    shortcut: KeyboardShortcut("n", modifiers: [.command, .option]),
                )
                item(BudgetText.openBudget, actions?.open)
                Divider()
                item(BudgetText.editBudgetEllipsis, actions?.edit, shortcut: KeyboardShortcut("e"))
                item(BudgetText.changeBudgetLimitEllipsis, actions?.changeLimit)
                item(BudgetText.duplicate, actions?.duplicate, shortcut: KeyboardShortcut("d"))
                Divider()
                item(BudgetText.showPreviousPeriod, actions?.showPrevious, shortcut: KeyboardShortcut("["))
                item(BudgetText.showNextPeriod, actions?.showNext, shortcut: KeyboardShortcut("]"))
                item(BudgetText.showCurrentPeriod, actions?.showCurrent)
                Divider()
                item(
                    BudgetText.deleteBudgetEllipsis,
                    actions?.delete,
                    shortcut: KeyboardShortcut(.delete),
                    role: .destructive,
                )
            }
        }

        private func item(
            _ title: String,
            _ action: (@MainActor () -> Void)?,
            shortcut: KeyboardShortcut? = nil,
            role: ButtonRole? = nil,
        ) -> some View {
            Button(title, role: role) { action?() }
                .disabled(action == nil)
                .keyboardShortcut(action == nil ? nil : shortcut)
        }
    }
#endif
