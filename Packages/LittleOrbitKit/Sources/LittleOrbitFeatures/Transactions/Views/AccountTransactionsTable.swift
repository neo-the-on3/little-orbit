#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitCore
    import LittleOrbitTheme
    import SwiftUI

    /// The macOS history table (Figma 28:1343): Upcoming first, then history newest first. Multi-select,
    /// double-click to edit, Delete key to delete (#23 platforms, AC 9). A scheduled occurrence's row opens its
    /// scheduled item instead, and isn't edited or deleted here (S85).
    struct AccountTransactionsTable: View {
        @Bindable var history: AccountHistoryViewModel
        let onEdit: (Set<UUID>) -> Void
        let onDelete: (Set<UUID>) -> Void
        /// Deleting waits while a Bulk Edit, or its Undo or Redo, runs in any window (D398).
        @Environment(WindowUndoHistory.self) private var undoHistory: WindowUndoHistory?

        private struct TableSection: Identifiable {
            let id: String
            let rows: [TransactionRowModel]
        }

        private var tableSections: [TableSection] {
            var sections: [TableSection] = []
            if !history.upcoming.isEmpty {
                sections.append(TableSection(id: "Upcoming · not in current balance", rows: history.upcoming))
            }
            let past = history.sections.flatMap(\.rows)
            if !past.isEmpty {
                sections.append(TableSection(id: "History · newest first", rows: past))
            }
            return sections
        }

        var body: some View {
            // How often the table's body runs, and what its rows cost, for Tester2's freeze breakdown (D405).
            let sections = BatchTrace.interval("ui.table.body") { tableSections }
            Table(of: TransactionRowModel.self, selection: $history.selection) {
                TableColumn("Date") { row in
                    Text(row.dateText)
                        .foregroundStyle(
                            row.isUpcoming ? Color(ThemeColor.labelSecondary) : Color(ThemeColor.labelPrimary)
                        )
                }
                .width(min: 90, ideal: 100)
                TableColumn("Payee") { row in
                    // A scheduled occurrence reads "Corner Bakery · Scheduled", the tag in grey (S85).
                    if row.isScheduled {
                        HStack(spacing: 0) {
                            Text(row.title)
                            Text(verbatim: " · " + HistoryScheduledText.tag)
                                .foregroundStyle(Color(ThemeColor.labelSecondary))
                        }
                    } else {
                        Text(row.title)
                    }
                }
                TableColumn("Category") { row in
                    Text(row.categoryText)
                }
                TableColumn("Account") { row in
                    Text(row.accountText)
                }
                TableColumn("Amount") { row in
                    Text(row.amountText)
                        .font(.theme(Typography.Amount.macOSBody))
                        .foregroundStyle(row.amountTone.color)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 90, ideal: 110)
                TableColumn("Balance") { row in
                    Text(row.balanceValueText)
                        .font(.theme(Typography.Amount.macOSBody))
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 90, ideal: 110)
            } rows: {
                ForEach(sections) { section in
                    Section(section.id) {
                        ForEach(section.rows) { row in
                            TableRow(row)
                        }
                    }
                }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if ids.count == 1, let id = ids.first, history.scheduledItemID(of: id) != nil {
                    // Not a stored transaction: it opens its scheduled item, with Pay and Skip (S85).
                    Button(HistoryScheduledText.openItem) { onEdit(ids) }
                } else if !history.storedIDs(ids).isEmpty {
                    let ids = history.storedIDs(ids)
                    Button(ids.count == 1 ? "Edit Transaction…" : "Edit \(ids.count) Transactions…") { onEdit(ids) }
                    Divider()
                    Button(
                        ids.count == 1 ? "Delete Transaction" : "Delete \(ids.count) Transactions…",
                        role: .destructive,
                    ) {
                        onDelete(ids)
                    }
                    .disabled(undoHistory?.isBatchRunning ?? false)
                }
            } primaryAction: { ids in
                onEdit(ids)
            }
            .onDeleteCommand {
                if !(undoHistory?.isBatchRunning ?? false) {
                    onDelete(history.selection)
                }
            }
        }
    }
#endif
