#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI
    import UniformTypeIdentifiers

    /// Search (#28 frames “Results/“cafe”” and “No results”): the system search field and scope bar, the summary
    /// card, then results grouped by day, newest first; on macOS a sortable table (#187). A tap, or a double-click
    /// in the table, opens the transaction to edit. An empty query lists every transaction. Export CSV saves the
    /// results. The view only lays out what `TransactionSearchViewModel` worked out.
    struct TransactionSearchView: View {
        let title: String
        let transactions: TransactionsFeature
        /// The iOS magnifying glass opens search ready to type.
        let focusesOnAppear: Bool
        @State private var model: TransactionSearchViewModel
        @State private var formSheet: TransactionFormSheet?
        @State private var isSearchPresented = false
        @FocusState private var isSearchFocused: Bool
        @Environment(WindowUndoHistory.self) private var undoHistory

        init(
            title: String,
            model: TransactionSearchViewModel,
            transactions: TransactionsFeature,
            focusesOnAppear: Bool = false,
        ) {
            self.title = title
            self.transactions = transactions
            self.focusesOnAppear = focusesOnAppear
            _model = State(initialValue: model)
        }

        var body: some View {
            results
                .overlay { emptyState }
                #if os(macOS)
                    // The footer shows only while a result is upcoming, and leaves no space otherwise (S85, S88).
                    .safeAreaInset(edge: .bottom) {
                        if let footer = model.upcomingFooter {
                            Text(footer)
                            .font(.theme(Typography.MacOS.footnote))
                            .foregroundStyle(Color(ThemeColor.labelSecondary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Spacing.space3)
                            .padding(.vertical, Spacing.space2)
                            .background(.bar)
                        }
                    }
                    .toolbar {
                        // The design's filter bar comes with the toolbar filters (#187); until then Export CSV is a
                        // toolbar button.
                        ToolbarItem {
                            exportButton(model.exportTitle)
                        }
                    }
                #endif
                // ⌘F puts the cursor in the search field (S30): the macOS toolbar field, and on iPad with a keyboard
                // the field above the list (#187). Esc clears it, as the field does.
                .background {
                    Button(model.prompt) { isSearchFocused = true }
                        .keyboardShortcut("f", modifiers: .command)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
                .navigationTitle(title)
                .searchable(
                    text: $model.query,
                    isPresented: $isSearchPresented,
                    placement: Self.placement,
                    prompt: Text(model.prompt),
                )
                .searchFocused($isSearchFocused)
                #if os(iOS)
                    // Presented search hides the bar's content by default, Back included, and iPad has no Cancel or
                    // close button, so search there had no way out without a keyboard. Keep Back on screen.
                    .searchPresentationToolbarBehavior(.avoidHidingContent)
                #endif
                .searchScopes($model.scope) {
                    ForEach(SearchScopeOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                // Typing searches after a short pause; each keystroke cancels the wait before it (Tech Architect NB2).
                // The search itself runs over the copy of the store the model keeps.
                .task(id: model.query) {
                    do {
                        try await Task.sleep(for: Self.typingPause)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else {
                        return
                    }
                    model.load()
                }
                .onChange(of: model.scope) { model.load() }
                // Any change to the shared store, from this window or another, or a restore, reads it again (S27).
                // That includes a save from a result's edit sheet, so the sheet doesn't load as well (NB6).
                .onChange(of: transactions.updates.revision) { model.load() }
                .task {
                    model.load()
                    if focusesOnAppear {
                        isSearchPresented = true
                    }
                }
                .sheet(item: $formSheet) { sheet in
                    TransactionFormView(model: sheet.model) { change in
                        undoHistory.record(change)
                    }
                }
                // Export CSV (#187): the system exporter saves the file the model made from the results on screen.
                .fileExporter(
                    isPresented: $model.isExporterPresented,
                    document: model.exportFile.map { SearchCSVDocument(data: $0.data) },
                    contentTypes: [.commaSeparatedText],
                    defaultFilename: model.exportFileName,
                    onCompletion: { result in
                        switch result {
                        case .success:
                            model.exportFinished(failed: false)
                        case .failure:
                            model.exportFinished(failed: true)
                        }
                    },
                    onCancellation: { model.exportFinished(failed: false) },
                )
                .alert(
                    model.exportFailure?.title ?? "",
                    isPresented: Binding(
                        get: { model.exportFailure != nil },
                        set: { if !$0 { model.exportFailure = nil } },
                    ),
                    presenting: model.exportFailure,
                ) { _ in
                    Button(model.okayTitle) {}
                } message: { failure in
                    Text(failure.message)
                }
        }

        // MARK: - Results

        /// iOS: a grouped list with the summary card and Export CSV first. macOS: the summary above a sortable
        /// table, with day headers only for a date sort (#187, S63).
        @ViewBuilder private var results: some View {
            #if os(macOS)
                VStack(alignment: .leading, spacing: 0) {
                    if !model.hints.isEmpty || model.summary != nil {
                        VStack(alignment: .leading, spacing: Spacing.space2) {
                            hintRows
                            if let summary = model.summary {
                                SearchSummaryView(summary: summary, note: nil)
                            }
                        }
                        .padding(.horizontal, Spacing.space3)
                        .padding(.vertical, Spacing.space2)
                    }
                    SearchResultsTable(model: model, onOpen: open)
                }
            #else
                List {
                    if !model.hints.isEmpty {
                        Section { hintRows }
                    }
                    if let summary = model.summary {
                        Section {
                            SearchSummaryView(summary: summary, note: model.upcomingNote)
                            // A row of its own, so VoiceOver reaches it apart from the summary it follows.
                            if model.canExport {
                                exportButton(model.exportRowTitle)
                            }
                        }
                    }
                    ForEach(model.sections) { section in
                        Section {
                            ForEach(section.rows) { resultRow($0) }
                        } header: {
                            SearchDayHeader(section: section)
                        }
                    }
                }
            #endif
        }

        /// “Export CSV…” in the macOS toolbar, “Export CSV” as the iOS row (D325.1).
        private func exportButton(_ title: String) -> some View {
            Button(title, systemImage: "square.and.arrow.up") { model.export() }
                .disabled(!model.canExport)
        }

        private func open(_ id: UUID) {
            formSheet = TransactionFormSheet(model: transactions.makeForm(.edit(id)))
        }

        // MARK: - Rows

        private var hintRows: some View {
            ForEach(model.hints, id: \.self) { hint in
                Label(hint, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color(ThemeColor.labelSecondary))
            }
        }

        private func resultRow(_ row: TransactionRowModel) -> some View {
            Button {
                open(row.id)
            } label: {
                TransactionRowView(row: row)
            }
            .buttonStyle(.plain)
            .accessibilityHint(model.openHint)
        }

        // MARK: - Empty states

        @ViewBuilder private var emptyState: some View {
            if let failure = model.failure {
                // A retry button comes with #187 (D320.6).
                ContentUnavailableView(
                    failure.title,
                    systemImage: "exclamationmark.triangle",
                    description: Text(failure.message),
                )
            } else if model.isNoResults {
                // The frame's wording and Clear Search, in the system's search empty state.
                ContentUnavailableView {
                    Label(model.noResultsTitle, systemImage: "magnifyingglass")
                } description: {
                    Text(model.noResultsMessage)
                } actions: {
                    Button(model.clearSearchTitle) { model.clear() }
                        .buttonStyle(.borderedProminent)
                }
            } else if model.isEmptyLedger {
                ContentUnavailableView(
                    model.emptyTitle,
                    systemImage: "list.bullet",
                    description: Text(model.emptyMessage),
                )
            }
        }

        /// How long typing has to pause before the results update.
        private static let typingPause = Duration.milliseconds(200)

        #if os(macOS)
            private static let placement = SearchFieldPlacement.toolbar
        #else
            private static let placement = SearchFieldPlacement.navigationBarDrawer(displayMode: .always)
        #endif
    }

    /// A day header: the day, then one figure per currency (D56, D107). Upcoming days are muted (label/tertiary)
    /// and VoiceOver says “Upcoming” first, so colour isn't the only signal (D120.1).
    struct SearchDayHeader: View {
        let section: SearchDaySection

        var body: some View {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(section.title)
                    Spacer()
                    Text(section.figuresText)
                }
                VStack(alignment: .leading) {
                    Text(section.title)
                    Text(section.figuresText)
                }
            }
            .font(.theme(Self.style))
            .foregroundStyle(Color(section.isUpcoming ? ThemeColor.labelTertiary : ThemeColor.labelSecondary))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(section.accessibilityLabel)
        }

        #if os(macOS)
            private static let style = Typography.MacOS.footnote
        #else
            private static let style = Typography.IOS.footnoteEmphasized
        #endif
    }

    /// The summary card: “14 results”, then Income, Expenses and Net per currency, or the amount moved when only
    /// transfers count (D17, D56). Amounts never truncate; at large sizes the figures stack.
    struct SearchSummaryView: View {
        let summary: SearchSummary
        let note: String?

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.space2) {
                Text(summary.countText)
                    .font(.theme(Self.headline))
                ForEach(summary.lines) { line in
                    VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                        Text(line.currencyCode)
                            .font(.theme(Self.caption))
                            .foregroundStyle(Color(ThemeColor.labelSecondary))
                        if let moved = line.movedText {
                            figure(moved, title: summary.movedTitle, tone: .neutral)
                        } else {
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: Spacing.space4) { figures(line) }
                                VStack(alignment: .leading, spacing: Spacing.space1) { figures(line) }
                            }
                        }
                    }
                }
                if let note {
                    Text(note)
                        .font(.theme(Self.caption))
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, Spacing.space1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([summary.accessibilityLabel, note].compactMap(\.self).joined(separator: ". "))
        }

        @ViewBuilder
        private func figures(_ line: SearchTotalsLine) -> some View {
            figure(line.incomeText ?? "", title: summary.incomeTitle, tone: .neutral)
            figure(line.expensesText ?? "", title: summary.expensesTitle, tone: .neutral)
            figure(line.netText ?? "", title: summary.netTitle, tone: line.netTone)
        }

        private func figure(_ amount: String, title: String, tone: AmountTone) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(amount)
                    .font(.theme(Self.amount))
                    .foregroundStyle(tone == .negative ? tone.color : Color(ThemeColor.labelPrimary))
                    .lineLimit(1)
                    .fixedSize()
                Text(title)
                    .font(.theme(Self.caption))
                    .foregroundStyle(Color(ThemeColor.labelSecondary))
            }
        }

        #if os(macOS)
            private static let headline = Typography.MacOS.headline
            private static let caption = Typography.MacOS.footnote
            private static let amount = Typography.Amount.macOSBody
        #else
            private static let headline = Typography.IOS.headline
            private static let caption = Typography.IOS.footnote
            private static let amount = Typography.Amount.iOSBody
        #endif
    }
#endif
