#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// Reports (#27 core). For Monday it lists one report, “What do I spend my money on?”; the other reports
    /// are a Follow-up to #27. iOS pushes it from the Accounts home, and macOS shows it for the sidebar's
    /// Reports item, inside its own navigation stack.
    public struct ReportsView: View {
        private let feature: ReportsFeature

        public init(feature: ReportsFeature) {
            self.feature = feature
        }

        public var body: some View {
            List {
                NavigationLink {
                    SpendingReportView(feature: feature)
                } label: {
                    Label(feature.spendingQuestion, systemImage: "cart.fill")
                }
            }
            .navigationTitle(feature.title)
        }
    }

    /// “What do I spend my money on?”: the period and currency pickers, the total, then one row per category
    /// with its amount, share and a bar, each opening its transactions. Standard list rows, so they get the
    /// system chevrons, Dynamic Type and keyboard focus.
    struct SpendingReportView: View {
        @State private var model: SpendingReportViewModel
        private let updates: LedgerUpdates

        init(feature: ReportsFeature) {
            _model = State(initialValue: feature.makeSpendingReport())
            updates = feature.updates
        }

        var body: some View {
            List {
                Section {
                    Text(ReportText.spendingQuestion)
                        .font(.title3)
                        .accessibilityAddTraits(.isHeader)
                    Picker(ReportText.period, selection: $model.period) {
                        ForEach(model.periods) { period in
                            Text(model.periodName(period)).tag(period)
                        }
                    }
                    .pickerStyle(.menu)
                    if model.showsCurrencyPicker {
                        Picker(ReportText.currency, selection: currency) {
                            ForEach(model.currencies, id: \.self) { code in
                                Text(code).tag(code)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                content
            }
            .navigationTitle(ReportText.spendingTitle)
            .task { model.load() }
            // Any edit to the shared store, from any window, regenerates the report.
            .onChange(of: updates.revision) { model.load(at: updates.revision) }
        }

        private var currency: Binding<String> {
            Binding(get: { model.currencyCode }, set: { model.selectCurrency($0) })
        }

        @ViewBuilder private var content: some View {
            if model.loadFailed {
                ContentUnavailableView(
                    model.loadFailedTitle,
                    systemImage: "exclamationmark.triangle",
                    description: Text(model.loadFailedMessage),
                )
            } else if model.isEmpty {
                ContentUnavailableView(model.emptyTitle, systemImage: "cart", description: Text(model.emptyMessage))
            } else if !model.rows.isEmpty {
                Section {
                    VStack(alignment: .leading) {
                        Text(model.totalText)
                            .font(.title.bold())
                            .monospacedDigit()
                            // Scales down rather than wrapping or truncating at narrow Mac widths (below about 440 pt).
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(model.totalCaption)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                Section {
                    ForEach(model.rows) { row in
                        NavigationLink {
                            SpendingTransactionsView(model: model, row: row, updates: updates)
                        } label: {
                            SpendingRowView(row: row)
                        }
                    }
                } header: {
                    Text(ReportText.allCategories)
                } footer: {
                    Text(ReportText.footer)
                }
            }
        }
    }

    /// One category row: icon, name and amount, then the transaction count and share, then a bar as long as
    /// the row's share of the largest row. A row at 0 or below (refund-only) has no bar. VoiceOver reads the
    /// row as one line of the data table: name, amount, currency, share and count.
    ///
    /// At accessibility text sizes (UI Designer's ruling on #185) every part gets its own full-width line, the
    /// icon first, so nothing is wider than the row: the name wraps between words, the amount stays whole on one
    /// line and scales down to fit, and the count and share scale a little rather than break inside a word.
    struct SpendingRowView: View {
        let row: SpendingRowModel
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    stacked
                } else {
                    standard
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.accessibilityLabel)
        }

        private var standard: some View {
            HStack(alignment: .top) {
                ReportCategoryIcon(symbolName: row.symbolName, hue: row.hue)
                VStack(alignment: .leading) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.name)
                        Spacer()
                        // An amount is never truncated (UI Designer, #82).
                        Text(row.amountText)
                            .monospacedDigit()
                            .foregroundStyle(row.amountTone.color)
                            .fixedSize()
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.countText)
                        Spacer()
                        if let share = row.shareText {
                            Text(share)
                                .monospacedDigit()
                                .fixedSize()
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    bar
                }
            }
        }

        private var stacked: some View {
            VStack(alignment: .leading) {
                ReportCategoryIcon(symbolName: row.symbolName, hue: row.hue)
                Text(row.name)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(row.amountText)
                    .monospacedDigit()
                    .foregroundStyle(row.amountTone.color)
                    .reportFullWidthLine(minimumScale: 0.5)
                Group {
                    Text(row.countText)
                        .reportFullWidthLine(minimumScale: 0.7)
                    if let share = row.shareText {
                        Text(share)
                            .monospacedDigit()
                            .reportFullWidthLine(minimumScale: 0.7)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                bar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        @ViewBuilder private var bar: some View {
            if let fraction = row.barFraction {
                ProgressView(value: fraction)
                    .tint(Color(row.hue.token))
            }
        }
    }

    extension View {
        /// At accessibility text sizes: one whole line across the row, scaled down to `minimumScale` to fit
        /// rather than wrapped, broken inside a word or clipped. It keeps its full line height, so it scales only
        /// for the row's width, never because a long name above it took the height.
        func reportFullWidthLine(minimumScale: CGFloat) -> some View {
            lineLimit(1)
                .minimumScaleFactor(minimumScale)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A category's icon chip: its white symbol on its `category/*` hue, as on the category screens. It grows with
    /// the text up to the largest standard size and no further, so at accessibility sizes it isn't clipped and
    /// leaves the row's text its width (Tester's AX5 check on #185).
    struct ReportCategoryIcon: View {
        let symbolName: String
        let hue: CategoryHue

        var body: some View {
            ReportCategoryChip(symbolName: symbolName, hue: hue)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    /// The chip itself, sized by the Dynamic Type size its parent allows.
    private struct ReportCategoryChip: View {
        let symbolName: String
        let hue: CategoryHue
        @ScaledMetric private var size: CGFloat = 32

        var body: some View {
            Image(systemName: symbolName)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color(hue.token), in: .circle)
                .accessibilityHidden(true)
        }
    }
#endif
