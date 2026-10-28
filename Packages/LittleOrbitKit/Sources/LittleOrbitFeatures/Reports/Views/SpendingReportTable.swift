#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitDomain
    import SwiftUI

    /// The Mac report body (#184 slice 3, UI Designer's spec): the total and caption, the chart with taller bars,
    /// then a table of every row in place of the iOS list. Double-click or Return on a row opens its drill-down.
    struct SpendingReportMacContent: View {
        let model: SpendingReportViewModel
        let open: (SpendingRowModel) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading) {
                    Text(model.totalText)
                        .font(.title.bold())
                        .monospacedDigit()
                        // Scales down rather than wrapping or truncating at narrow widths (below about 440 pt).
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(model.totalCaption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .padding(.horizontal)
                if !model.chartBars.isEmpty {
                    SpendingChartView(model: model, open: open)
                        .padding(.horizontal)
                }
                SpendingReportTable(model: model, open: open)
                // No fixedSize: the window takes its minimum size from this layout, and a vertically fixed
                // footer measured at its narrowest is one character per line, which grew the window past the
                // screen and stopped it shrinking (Tester2 on #310). It wraps to the width it's given.
                Text(model.footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding([.horizontal, .bottom])
            }
        }
    }

    /// Category | Transactions | Amount | Share, with the numbers right-aligned in monospaced digits.
    struct SpendingReportTable: View {
        let model: SpendingReportViewModel
        let open: (SpendingRowModel) -> Void
        @State private var selection: Set<SpendingRowModel.ID> = []

        var body: some View {
            Table(model.rows, selection: $selection) {
                TableColumn(model.chartCategoryAxis) { row in
                    Text(row.name)
                }
                TableColumn(model.transactionsColumn) { row in
                    Text(row.countNumberText)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                TableColumn(model.chartAmountAxis) { row in
                    Text(row.amountText)
                        .monospacedDigit()
                        .foregroundStyle(row.amountTone.color)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                TableColumn(model.shareColumn) { row in
                    Text(row.shareText ?? "")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .contextMenu(forSelectionType: SpendingRowModel.ID.self) { _ in
                EmptyView()
            } primaryAction: { ids in
                // Double-click or Return, even on a row still selected from before Back (#315).
                guard let row = model.tableRow(for: ids) else {
                    return
                }
                open(row)
            }
        }
    }
#endif
