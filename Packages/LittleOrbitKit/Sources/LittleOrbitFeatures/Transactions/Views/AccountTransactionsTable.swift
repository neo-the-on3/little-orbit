#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitTheme
    import SwiftUI

    /// The macOS history table (Figma 28:1343): Upcoming first, then history newest first. Multi-select,
    /// double-click to edit, Delete key to delete (#23 platforms, AC 9). A split's row expands to its lines
    /// (Figma 177:3867, S45); selecting a line selects its split.
    struct AccountTransactionsTable: View {
        @Bindable var history: AccountHistoryViewModel
        let onEdit: (Set<UUID>) -> Void
        let onDuplicate: (UUID) -> Void
        let onRefund: (UUID) -> Void
        let onDelete: (Set<UUID>) -> Void

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
            Table(of: TransactionRowModel.self, selection: selection) {
                TableColumn("Date") { row in
                    Text(row.dateText)
                        .foregroundStyle(
                            row.isUpcoming ? Color(ThemeColor.labelSecondary) : Color(ThemeColor.labelPrimary)
                        )
                }
                .width(min: 90, ideal: 100)
                TransactionTitleColumn.column()
                // Narrower than the title, so the title fits at the default window size (D234.1, D235.2).
                TableColumn("Category") { row in
                    Text(row.categoryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(row.categoryText)
                }
                .width(min: 100, ideal: 140)
                TableColumn("Account") { row in
                    Text(row.accountText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .width(min: 100, ideal: 140)
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
                ForEach(tableSections) { section in
                    Section(section.id) {
                        ForEach(section.rows) { row in
                            if row.splitLines.isEmpty {
                                TableRow(row)
                            } else {
                                DisclosureTableRow(row) {
                                    ForEach(row.splitLines) { line in
                                        TableRow(line)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .contextMenu(forSelectionType: UUID.self) { clicked in
                let ids = history.owningIDs(clicked)
                if !ids.isEmpty {
                    Button(ids.count == 1 ? "Edit Transaction…" : "Edit \(ids.count) Transactions…") { onEdit(ids) }
                    // One row offers Duplicate, a refund leaves it out, and several rows show it disabled (#31,
                    // S43; UI Designer, 23 Oct).
                    if ids.count == 1, let id = ids.first {
                        if !history.refundIDs.contains(id) {
                            DuplicateMenuButton { onDuplicate(id) }
                        }
                    } else {
                        Button("Duplicate") {}
                            .disabled(true)
                    }
                    // One expense offers Refund…; several rows show it disabled, and other rows leave it out
                    // (D117.3, #31).
                    if let id = history.refundTarget(ids) {
                        Button("Refund…") { onRefund(id) }
                    } else if ids.count > 1 {
                        Button("Refund…") {}
                            .disabled(true)
                    }
                    Divider()
                    Button(
                        ids.count == 1 ? "Delete Transaction" : "Delete \(ids.count) Transactions…",
                        role: .destructive,
                    ) {
                        onDelete(ids)
                    }
                }
            } primaryAction: { ids in
                onEdit(history.owningIDs(ids))
            }
            .onDeleteCommand {
                onDelete(history.selection)
            }
        }

        private var selection: Binding<Set<UUID>> {
            Binding(
                get: { history.selection },
                set: { history.selection = history.owningIDs($0) },
            )
        }
    }
#endif
