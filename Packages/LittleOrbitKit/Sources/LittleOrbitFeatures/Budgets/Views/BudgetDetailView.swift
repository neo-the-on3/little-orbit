#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The iOS budget detail (#25 design: the detail frames for on track, near limit, overspent, below 0, a
    /// previous period and no categories), pushed from a Budgets list row. The header shows the period on show
    /// with ‹ › to step through past periods, then any hints, the categories and the period's transactions. The
    /// ⋯ menu has Edit Budget, Change Budget Limit, a divider and Delete Budget, last and red. It reloads after every ledger change (#25
    /// AC 6); a budget deleted elsewhere says it no longer exists (D309).
    struct BudgetDetailView: View {
        @State private var model: BudgetDetailViewModel
        /// The Edit Budget sheet on show.
        @State private var form: BudgetFormViewModel?
        @State private var changesLimit = false
        @State private var confirmsDelete = false
        /// The window's Undo history, which records each change (D307.8).
        @Environment(WindowUndoHistory.self) private var undoHistory: WindowUndoHistory?
        @Environment(\.dismiss) private var dismiss
        private let feature: BudgetsFeature

        init(feature: BudgetsFeature, model: BudgetDetailViewModel) {
            self.feature = feature
            _model = State(initialValue: model)
        }

        var body: some View {
            content
                .navigationTitle(model.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if model.state == .figures || model.state == .noCategories {
                        ToolbarItem(placement: .primaryAction) {
                            actionsMenu
                        }
                    }
                }
                .sheet(item: $form) { form in
                    NavigationStack {
                        BudgetFormView(model: form)
                    }
                }
                .sheet(isPresented: $changesLimit) {
                    NavigationStack {
                        BudgetLimitView(model: model)
                    }
                }
                .confirmationDialog(model.deleteTitle, isPresented: $confirmsDelete, titleVisibility: .visible) {
                    Button(BudgetText.deleteBudget, role: .destructive) {
                        if model.delete() {
                            dismiss()
                        }
                    }
                    Button(CategoryText.cancel, role: .cancel) {}
                } message: {
                    Text(model.deleteMessage)
                }
                .alert(
                    model.alert?.title ?? "",
                    isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
                    presenting: model.alert,
                ) { _ in
                    Button(CategoryText.okay) { model.alert = nil }
                } message: { alert in
                    Text(alert.message)
                }
                .onAppear { model.load() }
                .onChange(of: feature.revision) { model.load() }
        }

        @ViewBuilder private var content: some View {
            switch model.state {
            case .loading:
                ProgressView()
            case .figures:
                figures
            case .noCategories:
                noCategories
            case .missing:
                // D311.7: the title alone, with no message or button; Back returns to the list.
                ContentUnavailableView {
                    Label(model.missingTitle, systemImage: HomeDestination.budgets.symbolName)
                }
            }
        }

        private var actionsMenu: some View {
            Menu {
                if feature.useCases.form != nil {
                    Button(BudgetText.editBudget, systemImage: "pencil") { openForm() }
                }
                if model.state == .figures {
                    Button(BudgetText.changeBudgetLimit, systemImage: "slider.horizontal.3") {
                        model.beginLimitChange()
                        changesLimit = true
                    }
                }
                Divider()
                Button(BudgetText.deleteBudget, systemImage: "trash", role: .destructive) {
                    confirmsDelete = true
                }
            } label: {
                Label(BudgetText.budgetActions, systemImage: "ellipsis.circle")
            }
        }

        // MARK: Figures

        @ViewBuilder private var figures: some View {
            List {
                if let header = model.header {
                    Section {
                        BudgetPeriodSwitcher(header: header, model: model)
                        BudgetDetailHeaderView(header: header)
                        ForEach(header.facts) { fact in
                            LabeledContent(fact.label) {
                                Text(fact.value)
                                    .monospacedDigit()
                                    .foregroundStyle(fact.tone.color)
                            }
                        }
                    }
                    if !header.hints.isEmpty {
                        Section {
                            ForEach(header.hints, id: \.self) { hint in
                                // Hints explain; nothing is wrong, so not a warning symbol (UI Designer).
                                Label(hint, systemImage: "info.circle")
                                    .font(.theme(Typography.IOS.footnote))
                                    .foregroundStyle(Color(ThemeColor.labelSecondary))
                            }
                        }
                    }
                }
                Section {
                    Text(model.categoriesText)
                } header: {
                    Text(model.categoriesHeader)
                } footer: {
                    if model.transactions.isEmpty {
                        Text(model.footnote)
                    }
                }
                if !model.transactions.isEmpty {
                    Section {
                        ForEach(model.transactions) { row in
                            BudgetTransactionRowView(row: row)
                        }
                    } header: {
                        Text(model.transactionsHeader)
                    } footer: {
                        Text(model.footnote)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }

        // MARK: No categories (D307.5)

        private var noCategories: some View {
            ContentUnavailableView {
                Label(model.noCategoriesTitle, systemImage: HomeDestination.budgets.symbolName)
            } description: {
                Text(model.noCategoriesMessage)
            } actions: {
                editButton
            }
            // The chart symbol is decorative, as on the Budgets empty state: VoiceOver gets the title, as a
            // heading, the message and the button.
            .accessibilityRepresentation {
                VStack {
                    Text(model.noCategoriesTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text(model.noCategoriesMessage)
                    editButton
                }
            }
        }

        @ViewBuilder private var editButton: some View {
            if feature.useCases.form != nil {
                Button(BudgetText.editBudget) { openForm() }
            }
        }

        private func openForm() {
            let history = undoHistory
            do {
                form = try feature.makeForm(.edit(model.budgetID), history: { history })
            } catch {
                model.alert = BudgetText.loadFailed
            }
        }
    }

    /// ‹ the period's dates › — the chevrons step through past periods; there are none after the current one.
    private struct BudgetPeriodSwitcher: View {
        let header: BudgetDetailHeader
        let model: BudgetDetailViewModel

        var body: some View {
            HStack(spacing: Spacing.space2) {
                Button(BudgetText.previousPeriod, systemImage: "chevron.left") { model.showPreviousPeriod() }
                    .disabled(!header.canShowPrevious)
                Spacer(minLength: Spacing.space2)
                Text(header.periodText)
                    .font(.theme(Typography.IOS.subheadlineEmphasized))
                    .foregroundStyle(Color(ThemeColor.labelSecondary))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                Spacer(minLength: Spacing.space2)
                Button(BudgetText.nextPeriod, systemImage: "chevron.right") { model.showNextPeriod() }
                    .disabled(!header.canShowNext)
            }
            .labelStyle(.iconOnly)
            // Each chevron is its own button in the row.
            .buttonStyle(.borderless)
            .frame(minHeight: Layout.minimumTargetIOS)
        }
    }

    /// What's left, unused or over, what's available, the bar, then spent and the timing.
    private struct BudgetDetailHeaderView: View {
        let header: BudgetDetailHeader

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.space2) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.space1) {
                    if let symbol = header.headlineSymbol {
                        Image(systemName: symbol)
                    }
                    Text(header.headline)
                        .monospacedDigit()
                }
                .font(.theme(Typography.IOS.title1))
                .foregroundStyle(headlineColor)
                Text(header.subline)
                    .font(.theme(Typography.IOS.subheadline).monospacedDigit())
                    .foregroundStyle(Color(ThemeColor.labelSecondary))
                if let progress = header.progress {
                    ProgressView(value: progress)
                        .tint(barColor)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.space2) {
                        spent
                        Spacer(minLength: Spacing.space2)
                        timing
                    }
                    VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                        spent
                        timing
                    }
                }
            }
            .padding(.vertical, Spacing.space1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(header.accessibilityLabel)
        }

        private var spent: some View {
            Text(header.spentText)
                .font(.theme(Typography.IOS.footnote).monospacedDigit())
                .foregroundStyle(Color(ThemeColor.labelSecondary))
        }

        /// Empty on a past period, whose subline already says when it ended (D311 amendment).
        @ViewBuilder private var timing: some View {
            if !header.timingText.isEmpty {
                Text(header.timingText)
                    .font(.theme(Typography.IOS.footnote))
                    .foregroundStyle(Color(ThemeColor.labelTertiary))
            }
        }

        private var headlineColor: Color {
            switch header.status {
            case .notStarted: Color(ThemeColor.labelSecondary)
            case .nothingSpent, .noCategories, .onTrack: Color(ThemeColor.labelPrimary)
            case .nearLimit: Color(ThemeColor.statusWarning)
            case .overspent: Color(ThemeColor.statusOverspent)
            }
        }

        private var barColor: Color {
            switch header.status {
            case .nearLimit: Color(ThemeColor.statusWarning)
            case .overspent: Color(ThemeColor.destructiveDefault)
            default: Color(ThemeColor.accentDefault)
            }
        }
    }

    /// One transaction in the budget's categories: icon, title (payee, or a refund title from D233), category
    /// and account (with “Split ·” for one line of a split, S73), then the amount and the date.
    private struct BudgetTransactionRowView: View {
        let row: BudgetTransactionRow
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    stacked
                } else {
                    ViewThatFits(in: .horizontal) {
                        inline
                        stacked
                    }
                }
            }
            .frame(minHeight: Layout.minimumTargetIOS)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.accessibilityLabel)
        }

        private var inline: some View {
            HStack(spacing: Spacing.space3) {
                AccountIconView(symbolName: row.symbolName)
                VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                    title.lineLimit(1)
                    subtitle.lineLimit(1)
                }
                Spacer(minLength: Spacing.space2)
                VStack(alignment: .trailing, spacing: Spacing.spaceHalf) {
                    amount
                    date
                }
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
            }
        }

        private var stacked: some View {
            VStack(alignment: .leading, spacing: Spacing.space1) {
                HStack(alignment: .center, spacing: Spacing.space3) {
                    AccountIconView(symbolName: row.symbolName)
                    title
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                subtitle
                    .fixedSize(horizontal: false, vertical: true)
                amount
                date
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var title: some View {
            Text(row.title)
                .font(.theme(Typography.IOS.body))
                .foregroundStyle(Color(ThemeColor.labelPrimary))
        }

        private var subtitle: some View {
            Text(row.subtitle)
                .font(.theme(Typography.IOS.footnote))
                .foregroundStyle(Color(ThemeColor.labelSecondary))
        }

        private var amount: some View {
            Text(row.amountText)
                .font(.theme(Typography.IOS.body).monospacedDigit())
                .foregroundStyle(row.tone.color)
        }

        private var date: some View {
            Text(row.dateText)
                .font(.theme(Typography.IOS.footnote))
                .foregroundStyle(Color(ThemeColor.labelTertiary))
        }
    }

    /// The Change Budget Limit sheet: the new limit, its error in red under the field, and “Was ₹7,000.00.”
    /// With past periods, Save asks “Change limit to …?” first, as the edit limit frame shows (#25 AC 4). With
    /// edits, Cancel or a swipe down asks “Discard Changes?” first (D300.1).
    private struct BudgetLimitView: View {
        @Bindable var model: BudgetDetailViewModel
        @State private var discard = DiscardConfirmation()
        @State private var confirms = false
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            Form {
                Section {
                    TextField(BudgetText.limitHeader, text: $model.limitText)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                        .accessibilityLabel(BudgetText.limitHeader)
                } header: {
                    Text(BudgetText.limitHeader)
                } footer: {
                    VStack(alignment: .leading, spacing: Spacing.space1) {
                        if let error = model.limitError {
                            Text(error)
                                .foregroundStyle(Color(ThemeColor.destructiveDefault))
                        }
                        Text(model.limitFootnote)
                    }
                }
            }
            .confirmsDiscardingChanges(isDirty: model.limitEdited, confirmation: $discard) { dismiss() }
            .navigationTitle(BudgetText.changeBudgetLimit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CategoryText.cancel) {
                        if discard.requestDismiss(isDirty: model.limitEdited, from: .cancel) {
                            dismiss()
                        }
                    }
                    .discardsChangesFromCancel(confirmation: $discard) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(CategoryText.save) { finish(model.changeLimit()) }
                        .disabled(!model.canChangeLimit)
                }
            }
            .confirmationDialog(model.limitConfirmationTitle, isPresented: $confirms, titleVisibility: .visible) {
                Button(BudgetText.applyFromThisPeriod) { finish(model.changeLimit(confirmed: true)) }
                Button(CategoryText.cancel, role: .cancel) {}
            } message: {
                Text(model.limitConfirmationMessage)
            }
        }

        private func finish(_ result: BudgetDetailViewModel.LimitChangeResult) {
            switch result {
            case .saved: dismiss()
            case .confirm: confirms = true
            // A budget deleted meanwhile (D309): the detail shows “Couldn’t Save Changes” once the sheet closes.
            case .notSaved where model.alert != nil: dismiss()
            case .notSaved: break
            }
        }
    }
#endif
