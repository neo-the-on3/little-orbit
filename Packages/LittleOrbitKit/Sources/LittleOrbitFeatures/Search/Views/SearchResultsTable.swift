#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitTheme
    import SwiftUI

    /// The macOS results table (#187): click a column title to sort. Sorted by date, in either direction, rows sit
    /// under their day headers; sorted by any other column, the list is flat (#28 AC, S63). Double-click or Return
    /// opens a transaction to edit. Columns are Date, Description, Payee, Category, Account and Amount (D325.4).
    /// Widths follow UI Designer's (6414565098), with lower minimums so the table fits the detail column beside the
    /// 240 pt sidebar at a 1100 pt window with no horizontal scroller (Tester 6418105253). Date is fixed at 96 pt.
    /// Description, the row's title, is 180–200 pt and grows with the window; Payee is 120–130 pt; Category and
    /// Account are 80–110 pt, so the less important right-hand columns give up their width first; those three go up
    /// to 200 pt. Amount is fixed at 124 pt, right-aligned and never cut. Text cells are cut at the end, with the full
    /// text on hover. A row with no description shows “Expense” or “Income” there in the secondary style (D328).
    struct SearchResultsTable: View {
        @Bindable var model: TransactionSearchViewModel
        let onOpen: (UUID) -> Void
        @State private var selection: UUID?

        var body: some View {
            Table(of: SearchTableRow.self, selection: $selection, sortOrder: $model.sortOrder) {
                TableColumn(model.dateColumnTitle, value: \.date) { row in
                    Text(row.row.dateText)
                        .foregroundStyle(
                            row.isUpcoming ? Color(ThemeColor.labelSecondary) : Color(ThemeColor.labelPrimary)
                        )
                        .lineLimit(1)
                }
                .width(96)
                TableColumn(model.descriptionColumnTitle, value: \.descriptionText) { row in
                    Text(row.descriptionText)
                        // Semantic styles, so the text follows the selected row's styling on macOS.
                        .foregroundStyle(
                            row.isDescriptionFallback
                                ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(row.descriptionText)
                }
                .width(min: 180, ideal: 200, max: .infinity)
                TableColumn(model.payeeColumnTitle, value: \.payee) { row in
                    Text(row.payee)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(row.payee)
                }
                .width(min: 120, ideal: 130, max: 200)
                TableColumn(model.categoryColumnTitle, value: \.category) { row in
                    Text(row.category)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(row.category)
                }
                .width(min: 80, ideal: 110, max: 200)
                TableColumn(model.accountColumnTitle, value: \.account) { row in
                    Text(row.account)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(row.account)
                }
                .width(min: 80, ideal: 110, max: 200)
                TableColumn(model.amountColumnTitle, value: \.amount) { row in
                    Text(row.row.amountText)
                        .font(.theme(Typography.Amount.macOSBody))
                        .foregroundStyle(row.row.amountTone.color)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(124)
            } rows: {
                if model.showsDayHeaders {
                    ForEach(model.tableSections) { section in
                        Section {
                            ForEach(section.rows) { row in
                                TableRow(row)
                            }
                        } header: {
                            SearchDayHeader(section: section.header)
                        }
                    }
                } else {
                    ForEach(model.tableRows) { row in
                        TableRow(row)
                    }
                }
            }
            .contextMenu(forSelectionType: UUID.self) { _ in
                EmptyView()
            } primaryAction: { ids in
                if let id = ids.first {
                    onOpen(id)
                }
            }
            .accessibilityHint(model.openHint)
        }
    }
#endif
