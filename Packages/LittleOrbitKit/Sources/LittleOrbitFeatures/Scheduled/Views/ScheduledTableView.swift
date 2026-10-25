#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The Mac Scheduled list as a Table (#26 frame "Scheduled – overdue, due today, upcoming, completed; sidebar
    /// badge", D340.13, D355): Due, Name, Account, Amount (trailing) and Status, with Repeat hidden until the header's
    /// context menu shows it (UI Designer on #205), in sections
    /// Overdue, Due Today, Upcoming and Completed with no counts (D334.2), each ordered by due date. Return or a
    /// double-click opens the item. With a row selected, ⌘E edits it, and ⌘⌫, the Delete key or Edit ▸ Delete asks
    /// to delete it. ⌘↩ waits for #201's Pay sheet (D360.2); the menu's Pay Now and Skip This Occurrence… have no
    /// shortcut. The catch-up and overdue hints sit above it, and the counts and the automatic line below it.
    /// Columns aren't sortable.
    struct ScheduledTableView: View {
        let model: ScheduledListViewModel
        /// Opens an item's screen in the caller's stack.
        let open: (UUID) -> Void
        @State private var selection: ScheduledTableRow.ID?
        /// Which columns show, their order and widths, per window: the header's context menu changes them.
        @SceneStorage("scheduledTableColumns")
        private var columnCustomization = TableColumnCustomization<ScheduledTableRow>()

        /// Stable column IDs for the saved customization.
        private enum ColumnID {
            static let due = "due"
            static let name = "name"
            static let repeatRule = "repeat"
            static let account = "account"
            static let amount = "amount"
            static let status = "status"
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                hints
                table
                footer
            }
        }

        @ViewBuilder private var hints: some View {
            if model.catchUpHint != nil || model.overdueHint != nil {
                VStack(alignment: .leading, spacing: Spacing.space2) {
                    if let hint = model.catchUpHint {
                        Label(hint, systemImage: "info.circle")
                            // Drawn: only now is it shown (D338.6). Keyed on the text, so a catch-up that
                            // replaces it while it's on screen is marked shown too (Tech Architect, #198).
                            .task(id: hint) { model.catchUpHintAppeared() }
                    }
                    if let hint = model.overdueHint {
                        Label(hint, systemImage: "exclamationmark.triangle")
                    }
                }
                .padding(Spacing.space3)
            }
        }

        private var table: some View {
            // Widths for a fresh 900 × 450 window with the 240-point sidebar, whose Table is about 642 points wide.
            // The five visible ideals add up to 520; with about 17 points of spacing per column, the 10-point
            // margin and the 19-point scroll bar that's 634, and the minimums (500) need 614. Name takes the extra
            // space. Repeat starts hidden (UI Designer on #205): the header's context menu shows it, and each window
            // keeps its own choice. Shown, it can scroll sideways in a narrow window.
            Table(of: ScheduledTableRow.self, selection: $selection, columnCustomization: $columnCustomization) {
                TableColumn(model.dueColumn) { row in
                    Text(verbatim: row.due)
                        .lineLimit(1)
                        .help(row.due)
                }
                .width(min: 88, ideal: 92, max: 140)
                .customizationID(ColumnID.due)
                TableColumn(model.nameColumn) { row in
                    Label {
                        Text(verbatim: row.name)
                    } icon: {
                        Image(systemName: row.row.symbolName)
                            .accessibilityHidden(true)
                    }
                    .lineLimit(1)
                    .help(row.name)
                }
                // The flexible column: down to 80 with its full name as help, and it takes any extra width.
                .width(min: 80, ideal: 88)
                .customizationID(ColumnID.name)
                TableColumn(model.repeatColumn) { row in
                    // "Monthly on the 30th or last day" needs about 191 points (D368): one line, truncating at the
                    // tail, with the full rule as help, as Status does. The item screen always shows the whole rule.
                    Text(verbatim: row.repeatText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(row.repeatText)
                }
                .width(min: 120, ideal: 200, max: 320)
                .customizationID(ColumnID.repeatRule)
                .defaultVisibility(.hidden)
                TableColumn(model.accountColumn) { row in
                    Text(verbatim: row.account)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(row.account)
                }
                .width(min: 112, ideal: 120, max: 240)
                .customizationID(ColumnID.account)
                TableColumn(model.amountColumn) { row in
                    Text(verbatim: row.amount)
                        .foregroundStyle(row.tone.color)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(row.amount)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 100, ideal: 100, max: 180)
                .customizationID(ColumnID.amount)
                TableColumn(model.statusColumn) { row in
                    // "Due today · Notifications off" needs about 175 points, more than the 120 minimum: it
                    // truncates, with the full text as help (UI Designer on #205).
                    Text(verbatim: row.status)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(row.status)
                }
                .width(min: 120, ideal: 120, max: 240)
                .customizationID(ColumnID.status)
            } rows: {
                ForEach(model.tableSections) { section in
                    Section(section.title) {
                        ForEach(section.rows) { row in
                            TableRow(row)
                        }
                    }
                }
            }
            .contextMenu(forSelectionType: ScheduledTableRow.ID.self) { ids in
                if let id = ids.first, let row = model.tableRow(id: id) {
                    ScheduledRowActions(model: model, row: row.row)
                }
            } primaryAction: { ids in
                // Return or a double-click.
                if let id = ids.first, let row = model.tableRow(id: id) {
                    open(row.row.itemID)
                }
            }
            // Edit ▸ Delete and the Delete key, the standard Mac path (Tech Architect NB 2).
            .onDeleteCommand {
                model.tableCommand(.delete, selection: selection)
            }
            .onKeyPress(keys: Self.shortcutKeys, phases: .down) { press in
                handle(press)
            }
        }

        /// Delete and E: with ⌘, the context menu's shortcuts. ⌘↩ isn't one until #201's Pay sheet is on this base,
        /// because it would record straight away (D360.2).
        private static let shortcutKeys: Set<KeyEquivalent> = [.delete, "e", "E"]

        /// ⌘E Edit… and ⌘⌫ Delete Scheduled Item… on the selected row only (D360.2). ⌘ must be held, with no other
        /// modifier; Caps Lock and the keypad flag don't count.
        private func handle(_ press: KeyPress) -> KeyPress.Result {
            guard press.modifiers.subtracting([.capsLock, .numericPad]) == .command else {
                return .ignored
            }
            let command: ScheduledTableCommand = press.key == .delete ? .delete : .edit
            return model.tableCommand(command, selection: selection) ? .handled : .ignored
        }

        @ViewBuilder private var footer: some View {
            let lines = [model.tableFooter, model.automaticFooter].compactMap { $0 }
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.space1) {
                    ForEach(lines, id: \.self) { Text(verbatim: $0) }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(Spacing.space3)
            }
        }
    }
#endif
