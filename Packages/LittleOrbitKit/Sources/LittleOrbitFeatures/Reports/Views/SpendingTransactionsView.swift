#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// A category's drill-down (#27): the row's total, then the transactions that add up to it, newest first.
    struct SpendingTransactionsView: View {
        let model: SpendingReportViewModel
        let row: SpendingRowModel
        @State private var drillDown: SpendingDrillDown?
        @State private var loadFailed = false
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            List {
                if let drillDown {
                    Section {
                        VStack(alignment: .leading) {
                            // As the report's total: one line, scaling down rather than breaking inside the number.
                            Text(drillDown.amountText)
                                .font(.title.bold())
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            // Wraps between words at large text sizes, never truncated.
                            Text(drillDown.caption)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Section(drillDown.countText) {
                        ForEach(drillDown.entries) { entry in
                            entryRow(entry)
                        }
                    }
                } else if loadFailed {
                    ContentUnavailableView(
                        model.loadFailedTitle,
                        systemImage: "exclamationmark.triangle",
                        description: Text(model.loadFailedMessage),
                    )
                }
            }
            .navigationTitle(drillDown?.title ?? row.name)
            .task { reload() }
            // The report reloaded, after any change to the store or another period, even when no row changed
            // (a payee rename): read the transactions again.
            .onChange(of: model.revision) { reload() }
        }

        /// At accessibility text sizes the amount moves under the title and subtitle, as in the report's rows, so
        /// the title keeps its width.
        private func entryRow(_ entry: SpendingEntryRowModel) -> some View {
            HStack {
                ReportCategoryIcon(symbolName: row.symbolName, hue: row.hue)
                ReportPairLayout(stacked: dynamicTypeSize.isAccessibilitySize, alignment: .center) {
                    VStack(alignment: .leading) {
                        Text(entry.title)
                        Text(entry.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } trailing: {
                    Text(entry.amountText)
                        .monospacedDigit()
                        .foregroundStyle(entry.amountTone.color)
                        .fixedSize()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.accessibilityLabel)
        }

        private func reload() {
            drillDown = model.drillDown(for: row)
            loadFailed = drillDown == nil
        }
    }
#endif
