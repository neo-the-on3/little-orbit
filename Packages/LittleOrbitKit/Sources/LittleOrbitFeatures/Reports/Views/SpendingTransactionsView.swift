#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// A category's drill-down (#27): the row's total, then the transactions that add up to it, newest first.
    struct SpendingTransactionsView: View {
        private let model: SpendingReportViewModel
        private let row: SpendingRowModel
        private let updates: LedgerUpdates
        @State private var drill: SpendingDrillDownModel
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        init(model: SpendingReportViewModel, row: SpendingRowModel, updates: LedgerUpdates) {
            self.model = model
            self.row = row
            self.updates = updates
            _drill = State(initialValue: model.makeDrillDown(for: row))
        }

        var body: some View {
            List {
                if let drillDown = drill.drillDown {
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
                } else if drill.loadFailed {
                    ContentUnavailableView(
                        model.loadFailedTitle,
                        systemImage: "exclamationmark.triangle",
                        description: Text(model.loadFailedMessage),
                    )
                }
            }
            .navigationTitle(drill.drillDown?.title ?? row.name)
            .task { drill.load() }
            // Any change to the shared store, from any window, reads the report and the transactions again, even
            // when no row changed (a payee rename) and while the report's list underneath isn't on screen.
            .onChange(of: updates.revision) { drill.refresh(at: updates.revision) }
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
    }
#endif
