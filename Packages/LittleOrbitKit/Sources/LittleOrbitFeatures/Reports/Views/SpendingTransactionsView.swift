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

        var body: some View {
            List {
                if let drillDown {
                    Section {
                        VStack(alignment: .leading) {
                            Text(drillDown.amountText)
                                .font(.title.bold())
                                .monospacedDigit()
                            Text(drillDown.caption)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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

        private func entryRow(_ entry: SpendingEntryRowModel) -> some View {
            HStack {
                ReportCategoryIcon(symbolName: row.symbolName, hue: row.hue)
                VStack(alignment: .leading) {
                    Text(entry.title)
                    Text(entry.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(entry.amountText)
                    .monospacedDigit()
                    .foregroundStyle(entry.amountTone.color)
                    .fixedSize()
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
