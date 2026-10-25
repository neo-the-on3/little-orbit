#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The Mac budget detail (#25 part 5, Mac Budgets detail frame), pushed from the list: the period on show
    /// with ‹ › and Today, what's left, unused or over, the bar and the figures, any hints, the categories, then
    /// the period's transactions in a table with Date, Payee, Category, Account and Amount (D239, D240). Its
    /// toolbar has the same actions as the Budget menu, which the list screen passes in.
    struct MacBudgetDetailView: View {
        let model: BudgetDetailViewModel
        let actions: BudgetMenuActions

        var body: some View {
            content
                .navigationTitle(model.name)
                // No subtitle: the ‹ › row already shows the period, and the list's count isn't for the detail
                // (UI Designer's #180 answer 6).
                .navigationSubtitle("")
                .toolbar {
                    if model.state == .figures || model.state == .noCategories {
                        ToolbarItemGroup(placement: .primaryAction) {
                            if let edit = actions.edit {
                                Button(BudgetText.editBudget, systemImage: "pencil", action: edit)
                                    .help(BudgetText.editBudget)
                            }
                            actionsMenu
                        }
                    }
                }
        }

        @ViewBuilder private var content: some View {
            switch model.state {
            case .loading:
                ProgressView()
            case .figures:
                figures
            case .noCategories:
                ContentUnavailableView {
                    Label(model.noCategoriesTitle, systemImage: HomeDestination.budgets.symbolName)
                } description: {
                    Text(model.noCategoriesMessage)
                } actions: {
                    if let edit = actions.edit {
                        Button(BudgetText.editBudgetEllipsis, action: edit)
                    }
                }
            case .missing:
                // D311.7: the title alone, with no message or button; Back returns to the list.
                ContentUnavailableView {
                    Label(model.missingTitle, systemImage: HomeDestination.budgets.symbolName)
                }
            }
        }

        private var actionsMenu: some View {
            Menu {
                if let changeLimit = actions.changeLimit {
                    Button(BudgetText.changeBudgetLimitEllipsis, action: changeLimit)
                }
                // Dimmed, not hidden, for a budget with no categories, as in the other two menus (D313.3).
                Button(BudgetText.duplicate) { actions.duplicate?() }
                    .disabled(actions.duplicate == nil)
                Divider()
                if let delete = actions.delete {
                    Button(BudgetText.deleteBudgetEllipsis, role: .destructive, action: delete)
                }
            } label: {
                Label(BudgetText.budgetActions, systemImage: "ellipsis.circle")
            }
            .help(BudgetText.budgetActions)
        }

        // MARK: Figures

        private var figures: some View {
            VStack(alignment: .leading, spacing: 0) {
                if let header = model.header {
                    MacBudgetDetailHeader(header: header, model: model)
                        .padding(Layout.marginMacOS)
                }
                Divider()
                if model.transactions.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    transactionsTable
                }
                Text(model.footnote)
                    .font(.theme(Typography.MacOS.footnote))
                    .foregroundStyle(Color(ThemeColor.labelSecondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.space3)
            }
        }

        /// D239, D240: Payee is the widest column and truncates with its full title on hover; Category and
        /// Account keep at least 120 pt, Category with its full name on hover and “Split ·” always shown; the
        /// date and the amount are never cut. There's no Balance column.
        private var transactionsTable: some View {
            Table(model.transactions) {
                TableColumn(BudgetText.dateColumn) { row in
                    Text(row.fullDateText)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .width(min: 90, ideal: 110)
                TableColumn(BudgetText.payeeColumn) { row in
                    Label {
                        Text(row.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } icon: {
                        Image(systemName: row.symbolName)
                            .foregroundStyle(Color(ThemeColor.labelSecondary))
                    }
                    .help(row.title)
                }
                .width(min: 160, ideal: 300)
                TableColumn(BudgetText.categoryColumn) { row in
                    Text(row.categoryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(row.categoryText)
                }
                .width(min: 120, ideal: 140)
                TableColumn(BudgetText.accountColumn) { row in
                    Text(row.accountText)
                        .lineLimit(1)
                        .help(row.accountText)
                }
                .width(min: 120, ideal: 140)
                TableColumn(BudgetText.amountColumn) { row in
                    Text(row.amountText)
                        .font(.theme(Typography.Amount.macOSBody))
                        .foregroundStyle(row.tone.color)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityLabel(row.accessibilityLabel)
                }
                .width(min: 100, ideal: 120)
            }
        }
    }

    /// The detail's header: ‹ the period › Today with the timing on the right, then the headline, the
    /// subline, the bar, the figures, any hints and the categories.
    private struct MacBudgetDetailHeader: View {
        let header: BudgetDetailHeader
        let model: BudgetDetailViewModel

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.space3) {
                HStack(spacing: Spacing.space2) {
                    HStack(spacing: Spacing.space1) {
                        Button(BudgetText.previousPeriod, systemImage: "chevron.left") { model.showPreviousPeriod() }
                            .disabled(!header.canShowPrevious)
                            .help(BudgetText.showPreviousPeriod)
                        Text(header.periodText)
                            .font(.theme(Typography.MacOS.headline))
                            .monospacedDigit()
                            .fixedSize()
                        Button(BudgetText.nextPeriod, systemImage: "chevron.right") { model.showNextPeriod() }
                            .disabled(!header.canShowNext)
                            .help(BudgetText.showNextPeriod)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    Button(BudgetText.today) { model.showCurrentPeriod() }
                        .disabled(!model.canShowCurrentPeriod)
                        .help(BudgetText.showCurrentPeriod)
                    Spacer(minLength: Spacing.space2)
                    // Empty on a past period, whose subline already says when it ended (D311 amendment).
                    if !header.timingText.isEmpty {
                        Text(header.timingText)
                            .font(.theme(Typography.MacOS.subheadline))
                            .foregroundStyle(Color(ThemeColor.labelSecondary))
                            .fixedSize()
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.space2) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.space1) {
                        if let symbol = header.headlineSymbol {
                            Image(systemName: symbol)
                        }
                        Text(header.headline)
                            .monospacedDigit()
                    }
                    .font(.theme(Typography.Amount.macOSTitle))
                    .foregroundStyle(MacBudgetStyle.headlineColor(header.status))
                    Text(header.subline)
                        .font(.theme(Typography.MacOS.subheadline).monospacedDigit())
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                    if let progress = header.progress {
                        ProgressView(value: progress)
                            .tint(MacBudgetStyle.barColor(header.status))
                    }
                    Text(header.spentText)
                        .font(.theme(Typography.MacOS.subheadline).monospacedDigit())
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(header.accessibilityLabel)
                if !header.facts.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: Spacing.space4, verticalSpacing: Spacing.space1) {
                        ForEach(header.facts) { fact in
                            GridRow {
                                Text(fact.label)
                                    .foregroundStyle(Color(ThemeColor.labelSecondary))
                                Text(fact.value)
                                    .monospacedDigit()
                                    .foregroundStyle(fact.tone.color)
                                    .fixedSize()
                            }
                        }
                    }
                    .font(.theme(Typography.MacOS.body))
                }
                ForEach(header.hints, id: \.self) { hint in
                    // Hints explain; nothing is wrong, so not a warning symbol (UI Designer).
                    Label(hint, systemImage: "info.circle")
                        .font(.theme(Typography.MacOS.footnote))
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                        // A long hint wraps, even when a short window leaves the header little room.
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(model.categoriesLine)
                    .font(.theme(Typography.MacOS.footnote))
                    .foregroundStyle(Color(ThemeColor.labelSecondary))
                    .textSelection(.enabled)
            }
        }
    }
#endif
