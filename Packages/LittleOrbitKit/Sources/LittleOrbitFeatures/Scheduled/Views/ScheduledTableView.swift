#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The Mac Scheduled list as a Table (#26 frame "Scheduled – overdue, due today, upcoming, completed; sidebar
    /// badge", D340.13): Due 96, Name 180, Repeat 150, Account 120, Amount 120 (trailing) and Status filling the rest,
    /// in sections Overdue, Due Today, Upcoming and "Completed · 1", each ordered by due date. Return or a
    /// double-click opens the item. With a row selected, ⌘↩ pays it, ⌘E edits it and ⌘⌫ asks to delete it; Skip This
    /// Occurrence… has no shortcut. The catch-up and overdue hints sit above it, and the counts and the automatic
    /// line below it. Columns aren't sortable.
    struct ScheduledTableView: View {
        let model: ScheduledListViewModel
        /// Opens an item's screen in the caller's stack.
        let open: (UUID) -> Void
        @State private var selection: ScheduledTableRow.ID?

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
                    }
                    if let hint = model.overdueHint {
                        Label(hint, systemImage: "exclamationmark.triangle")
                    }
                }
                .padding(Spacing.space3)
            }
        }

        private var table: some View {
            Table(of: ScheduledTableRow.self, selection: $selection) {
                TableColumn(model.dueColumn) { row in
                    Text(verbatim: row.due)
                }
                .width(ideal: 96)
                TableColumn(model.nameColumn) { row in
                    Label {
                        Text(verbatim: row.name)
                    } icon: {
                        Image(systemName: row.row.symbolName)
                            .accessibilityHidden(true)
                    }
                }
                .width(ideal: 180)
                TableColumn(model.repeatColumn) { row in
                    Text(verbatim: row.repeatText)
                }
                .width(ideal: 150)
                TableColumn(model.accountColumn) { row in
                    Text(verbatim: row.account)
                }
                .width(ideal: 120)
                TableColumn(model.amountColumn) { row in
                    Text(verbatim: row.amount)
                        .foregroundStyle(row.tone.color)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(ideal: 120)
                TableColumn(model.statusColumn) { row in
                    Text(verbatim: row.status)
                        .foregroundStyle(.secondary)
                }
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
            .onKeyPress(keys: [.return, .delete, "e"], phases: .down) { press in
                handle(press)
            }
        }

        /// ⌘↩ Pay Now, ⌘E Edit…, ⌘⌫ Delete Scheduled Item… on the selected row, as the context menu shows them.
        private func handle(_ press: KeyPress) -> KeyPress.Result {
            guard press.modifiers == .command, let id = selection, let row = model.tableRow(id: id)?.row else {
                return .ignored
            }
            switch press.key {
            case .return:
                guard row.canSettle else {
                    return .ignored
                }
                model.payNow(row)
            case .delete:
                model.confirmDelete(row.itemID)
            default:
                model.openEditor(row.itemID)
            }
            return .handled
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
