#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitTheme
    import SwiftUI

    /// The Mac All Transactions table (#243, D421): the account register's table and actions, with Description,
    /// Payee and Account columns and no Balance column (D421.3, D421.4). Fixed order for 1.0, newest first under
    /// day headers (D425.2). Multi-select; double-click or Return opens, the Delete key deletes (D421.6–D421.8).
    struct AllTransactionsTable: View {
        @Bindable var model: AllTransactionsViewModel
        let onEdit: (Set<UUID>) -> Void
        let onDelete: (Set<UUID>) -> Void
        /// Deleting waits while a Bulk Edit, or its Undo or Redo, runs in any window (D398).
        @Environment(WindowUndoHistory.self) private var undoHistory: WindowUndoHistory?

        private var isBatchRunning: Bool { undoHistory?.isBatchRunning ?? false }

        var body: some View {
            Table(of: AllTransactionsRow.self, selection: $model.selection) {
                TableColumn("Date") { item in
                    Text(item.row.dateText)
                        .foregroundStyle(
                            item.isUpcoming ? Color(ThemeColor.labelSecondary) : Color(ThemeColor.labelPrimary)
                        )
                        .lineLimit(1)
                }
                .columnWidth(.date)
                TableColumn("Description") { item in
                    Text(item.descriptionText)
                        .foregroundStyle(
                            item.isDescriptionFallback
                                ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(item.descriptionText)
                }
                .columnWidth(.description)
                TableColumn("Payee") { item in
                    textCell(item.payee)
                }
                .columnWidth(.payee)
                TableColumn("Category") { item in
                    textCell(item.row.categoryText)
                }
                .columnWidth(.category)
                TableColumn("Account") { item in
                    textCell(item.row.accountText)
                }
                .columnWidth(.account)
                TableColumn("Amount") { item in
                    Text(item.row.amountText)
                        .font(.theme(Typography.Amount.macOSBody))
                        .foregroundStyle(item.row.amountTone.color)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .columnWidth(.amount)
            } rows: {
                ForEach(model.sections) { section in
                    Section(section.title) {
                        ForEach(section.rows) { item in
                            TableRow(item)
                        }
                    }
                }
            }
            // The register's menu and strings; an empty-area right-click shows none.
            .contextMenu(forSelectionType: UUID.self) { ids in
                if !ids.isEmpty {
                    Button(ids.count == 1 ? "Edit Transaction…" : "Edit \(ids.count) Transactions…") { onEdit(ids) }
                    Divider()
                    Button(
                        ids.count == 1 ? "Delete Transaction" : "Delete \(ids.count) Transactions…",
                        role: .destructive,
                    ) {
                        onDelete(ids)
                    }
                    .disabled(isBatchRunning)
                }
            } primaryAction: { ids in
                onEdit(ids)
            }
            .onDeleteCommand {
                if !isBatchRunning {
                    onDelete(model.selection)
                }
            }
        }

        private func textCell(_ text: String) -> some View {
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(text)
        }
    }

    extension TableColumn {
        /// The column's width from `AllTransactionsColumnSpec`: fixed, or flexible for the one column that
        /// takes the slack (D-ruling 6486981842).
        fileprivate func columnWidth(_ column: AllTransactionsColumn) -> TableColumn<RowValue, Sort, Content, Label> {
            let width = AllTransactionsColumnSpec.width(for: column)
            return self.width(
                min: CGFloat(width.min),
                ideal: CGFloat(width.ideal),
                max: width.max.map { CGFloat($0) },
            )
        }
    }
#endif
