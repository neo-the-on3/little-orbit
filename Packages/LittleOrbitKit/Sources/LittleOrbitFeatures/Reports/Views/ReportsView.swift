#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// Reports (#27 core): This Month's summary (#184 slice 5), then “What do I spend my money on?”, by payee
    /// “Where do I spend the most?” (slice 4), “Where does my money come from?” and “How much do I earn compared to
    /// my expenses?” (slice 5). iOS pushes it from the Accounts home, and macOS shows it for the sidebar's
    /// Reports item, inside its own navigation stack.
    public struct ReportsView: View {
        private let feature: ReportsFeature
        /// This Month's Spent, Earned and Left over at the top (#184 slice 5).
        @State private var summary: ReportsSummaryModel

        public init(feature: ReportsFeature) {
            self.feature = feature
            _summary = State(initialValue: feature.makeSummary())
        }

        public var body: some View {
            List {
                ReportsSummarySection(model: summary)
                Section {
                    links
                }
            }
            .navigationTitle(feature.title)
            .task { await summary.load() }
            .onChange(of: feature.updates.revision) {
                let revision = feature.updates.revision
                Task { await summary.load(at: revision) }
            }
        }

        @ViewBuilder private var links: some View {
            NavigationLink {
                SpendingReportView(feature: feature)
            } label: {
                Label(feature.spendingQuestion, systemImage: "cart.fill")
            }
            NavigationLink {
                SpendingReportView(feature: feature, grouping: .payee)
            } label: {
                Label(feature.payeeQuestion, systemImage: "storefront.fill")
            }
            NavigationLink {
                SpendingReportView(feature: feature, flow: .income)
            } label: {
                Label(feature.incomeQuestion, systemImage: "banknote.fill")
            }
            NavigationLink {
                IncomeExpenseReportView(feature: feature)
            } label: {
                Label(feature.incomeExpenseQuestion, systemImage: "chart.bar.xaxis")
            }
        }
    }

    /// “What do I spend my money on?”: the period and currency pickers, the total, the ranked bar chart (#184
    /// slice 3), then one row per category with its amount, share and a bar, each opening its transactions.
    /// Grouped by payee it's “Where do I spend the most?” (#184 slice 4), with one row per payee and no icons;
    /// counting income it's “Where does my money come from?” (slice 5).
    /// Standard list rows, so they get the system chevrons, Dynamic Type and keyboard focus. On the Mac a table
    /// replaces the list.
    struct SpendingReportView: View {
        @State private var model: SpendingReportViewModel
        @State private var showsAccounts = false
        /// The row a chart bar or a Mac table row opened. Back forgets it, so the same row opens again (#315).
        @State private var opened = ReportDrillDownPresentation<SpendingRowModel>()
        private let updates: LedgerUpdates

        init(feature: ReportsFeature, grouping: ReportGrouping = .category, flow: ReportFlow = .spending) {
            let model =
                if flow == .income {
                    feature.makeIncomeReport()
                } else if grouping == .payee {
                    feature.makePayeeReport()
                } else {
                    feature.makeSpendingReport()
                }
            _model = State(initialValue: model)
            updates = feature.updates
        }

        var body: some View {
            layout
                .navigationTitle(model.navigationTitle)
                .toolbar {
                    ToolbarItem {
                        Button {
                            showsAccounts = true
                        } label: {
                            Label(model.accountsTitle, systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityValue(model.accountsValue)
                        .disabled(model.accounts.isEmpty)
                    }
                }
                .sheet(isPresented: $showsAccounts) {
                    ReportAccountsSheet(model: model)
                }
                .navigationDestination(isPresented: $opened.isPresented) {
                    if let row = opened.row {
                        SpendingTransactionsView(model: model, row: row, updates: updates)
                    }
                }
                .task { await model.load() }
                // Any edit to the shared store, from any window, regenerates the report.
                .onChange(of: updates.revision) {
                    let revision = updates.revision
                    Task { await model.load(at: revision) }
                }
        }

        @ViewBuilder private var layout: some View {
            #if os(macOS)
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading) {
                        controls
                    }
                    .padding([.horizontal, .top])
                    if model.loadFailed {
                        ReportLoadFailedView(model: model) { await model.retry() }
                            .frame(maxHeight: .infinity)
                    } else if model.isEmpty {
                        emptyView
                            .frame(maxHeight: .infinity)
                    } else if !model.rows.isEmpty {
                        SpendingReportMacContent(model: model) { opened.open($0) }
                    } else {
                        Spacer()
                    }
                }
            #else
                List {
                    Section {
                        controls
                    }
                    content
                }
            #endif
        }

        @ViewBuilder private var controls: some View {
            Text(model.question)
                .font(.title3)
                .accessibilityAddTraits(.isHeader)
            ReportPeriodControls(model: model)
            if model.showsCurrencyPicker {
                Picker(ReportText.currency, selection: currency) {
                    ForEach(model.currencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                .pickerStyle(.segmented)
            }
        }

        private var emptyView: some View {
            ContentUnavailableView(
                model.emptyTitle,
                systemImage: model.emptySymbolName,
                description: Text(model.emptyMessage),
            )
        }

        private var currency: Binding<String> {
            Binding(get: { model.currencyCode }, set: { code in Task { await model.selectCurrency(code) } })
        }

        @ViewBuilder private var content: some View {
            if model.loadFailed {
                ReportLoadFailedView(model: model) { await model.retry() }
            } else if model.isEmpty {
                emptyView
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
                if !model.chartBars.isEmpty {
                    Section {
                        SpendingChartView(model: model) { opened.open($0) }
                    }
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
                    Text(model.rowsHeader)
                } footer: {
                    Text(model.footer)
                }
            }
        }
    }

    /// One category or payee row: icon (a category's only), name and amount, then the transaction count and share, then a bar as long as
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
                if let symbolName = row.symbolName, let hue = row.hue {
                    ReportCategoryIcon(symbolName: symbolName, hue: hue)
                }
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
                if let symbolName = row.symbolName, let hue = row.hue {
                    ReportCategoryIcon(symbolName: symbolName, hue: hue)
                }
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
                    .tint(row.hue.map { Color($0.token) } ?? Color.accentColor)
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
