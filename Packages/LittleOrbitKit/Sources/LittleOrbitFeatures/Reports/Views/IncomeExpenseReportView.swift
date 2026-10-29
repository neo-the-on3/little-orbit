#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// “How much do I earn compared to my expenses?” (#184 slice 5, D420): the period controls, Earned, Spent and
    /// Left over, the grouped bar chart, then one row a month, newest first. On the Mac a table, oldest month first
    /// with a Total row, replaces the rows. Tapping a month does nothing in 1.0.
    struct IncomeExpenseReportView: View {
        @State private var model: IncomeExpenseReportViewModel
        @State private var showsAccounts = false
        private let updates: LedgerUpdates

        init(feature: ReportsFeature) {
            _model = State(initialValue: feature.makeIncomeExpenseReport())
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
                .task { await model.load() }
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
                    if model.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if model.loadFailed {
                        ReportLoadFailedView(model: model) { await model.retry() }
                            .frame(maxHeight: .infinity)
                    } else if model.isEmpty {
                        emptyView
                            .frame(maxHeight: .infinity)
                    } else {
                        header
                            .padding(.horizontal)
                        IncomeExpenseChartView(model: model)
                            .padding(.horizontal)
                        IncomeExpenseTable(model: model)
                        Text(model.footer)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding([.horizontal, .bottom])
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

        private var header: some View {
            VStack(alignment: .leading, spacing: 8) {
                ReportValuesView(values: model.values)
                Text(model.caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        private var emptyView: some View {
            ContentUnavailableView(
                model.emptyTitle,
                systemImage: "chart.bar.xaxis",
                description: Text(model.emptyMessage),
            )
        }

        private var currency: Binding<String> {
            Binding(get: { model.currencyCode }, set: { code in Task { await model.selectCurrency(code) } })
        }

        @ViewBuilder private var content: some View {
            if model.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if model.loadFailed {
                ReportLoadFailedView(model: model) { await model.retry() }
            } else if model.isEmpty {
                emptyView
            } else {
                Section {
                    header
                }
                Section {
                    IncomeExpenseChartView(model: model)
                }
                Section {
                    ForEach(model.rows) { row in
                        IncomeExpenseRowView(row: row)
                    }
                } footer: {
                    Text(model.footer)
                }
            }
        }
    }

    /// One month: “Oct 2026” with its left over trailing, then “In ₹… · Out ₹…”. VoiceOver reads it as one
    /// line. At accessibility text sizes each part gets its own full-width line, as in the other reports' rows.
    struct IncomeExpenseRowView: View {
        let row: IncomeExpenseRowModel
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading) {
                        Text(row.title)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(row.leftOverText)
                            .monospacedDigit()
                            .foregroundStyle(row.leftOverTone.color)
                            .reportFullWidthLine(minimumScale: 0.5)
                        Text(row.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.title)
                            Spacer()
                            Text(row.leftOverText)
                                .monospacedDigit()
                                .foregroundStyle(row.leftOverTone.color)
                                .fixedSize()
                        }
                        Text(row.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.accessibilityLabel)
        }
    }

    #if os(macOS)
        /// Month | Income | Expenses | Left over, oldest month first, then the Total row in bold, the numbers
        /// right-aligned in monospaced digits.
        struct IncomeExpenseTable: View {
            let model: IncomeExpenseReportViewModel

            var body: some View {
                Table(model.tableRows) {
                    TableColumn(model.monthColumn) { row in
                        Text(row.title)
                            .fontWeight(row.isTotal ? .semibold : nil)
                    }
                    TableColumn(model.incomeColumn) { row in
                        amount(row.incomeText, tone: .neutral, total: row.isTotal)
                    }
                    TableColumn(model.expensesColumn) { row in
                        amount(row.expensesText, tone: .neutral, total: row.isTotal)
                    }
                    TableColumn(model.leftOverColumn) { row in
                        amount(row.leftOverText, tone: row.leftOverTone, total: row.isTotal)
                    }
                }
            }

            private func amount(_ text: String, tone: AmountTone, total: Bool) -> some View {
                Text(text)
                    .monospacedDigit()
                    .fontWeight(total ? .semibold : nil)
                    .foregroundStyle(tone.color)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    #endif
#endif
