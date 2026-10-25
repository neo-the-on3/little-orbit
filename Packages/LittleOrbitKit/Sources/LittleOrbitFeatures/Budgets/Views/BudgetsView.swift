#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The iOS Budgets list (#25 design: Budgets list and Budgets empty frames), pushed from the home screen's
    /// Budgets row. Each row shows the status, a bar, spent of what's available and the days left, and opens
    /// the budget. It reloads after every ledger change (#25 AC 6).
    public struct BudgetsView: View {
        @State private var model: BudgetsViewModel
        private let feature: BudgetsFeature

        public init(feature: BudgetsFeature) {
            self.feature = feature
            _model = State(initialValue: feature.makeList())
        }

        public var body: some View {
            List {
                if !model.rows.isEmpty {
                    Section {
                        ForEach(model.rows) { row in
                            NavigationLink {
                                // The budget detail is #25 part 4. A budget with no categories opens there too,
                                // to D307's "No Categories" empty state (D308 amendment 2).
                                UpcomingFeatureView(
                                    title: row.name,
                                    systemImage: HomeDestination.budgets.symbolName,
                                    message: "The budget detail arrives with its own part of #25.",
                                )
                            } label: {
                                BudgetRowView(row: row)
                            }
                        }
                    } footer: {
                        Text(BudgetsViewModel.footnote)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay { emptyState }
            .navigationTitle(BudgetsViewModel.title)
            .navigationBarTitleDisplayMode(.large)
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

        @ViewBuilder private var emptyState: some View {
            if model.isEmpty {
                ContentUnavailableView(
                    BudgetsViewModel.emptyTitle,
                    systemImage: HomeDestination.budgets.symbolName,
                    description: Text(BudgetsViewModel.emptyMessage),
                )
                // The chart symbol is decorative. As on Payees (#156), VoiceOver gets just the title, as a
                // heading, and the message.
                .accessibilityRepresentation {
                    VStack {
                        Text(BudgetsViewModel.emptyTitle)
                            .accessibilityAddTraits(.isHeader)
                        Text(BudgetsViewModel.emptyMessage)
                    }
                }
            }
        }
    }

    /// One budget row: the name and status, the bar, then spent of what's available and the timing. Before the
    /// start date there's no bar (D308 amendment), and with no categories only the name and status (D308
    /// amendment 2).
    struct BudgetRowView: View {
        let row: BudgetRow

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.space1 + Spacing.spaceHalf) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.space2) {
                        name
                        Spacer(minLength: Spacing.space2)
                        status
                    }
                    VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                        name
                        status
                    }
                }
                if let progress = row.progress {
                    ProgressView(value: progress)
                        .tint(barColor)
                }
                if let amountsText = row.amountsText, let timingText = row.timingText {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.space2) {
                            amounts(amountsText)
                            Spacer(minLength: Spacing.space2)
                            timing(timingText)
                        }
                        VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                            amounts(amountsText)
                            timing(timingText)
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.space1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.accessibilityLabel)
        }

        private var name: some View {
            Text(row.name)
                .font(.theme(Typography.IOS.body))
                .foregroundStyle(Color(ThemeColor.labelPrimary))
        }

        private var status: some View {
            HStack(spacing: Spacing.space1) {
                if let symbol = row.statusSymbol {
                    Image(systemName: symbol)
                }
                Text(row.statusText)
                    .monospacedDigit()
            }
            .font(.theme(Typography.IOS.subheadlineEmphasized))
            .foregroundStyle(statusColor)
        }

        private func amounts(_ text: String) -> some View {
            Text(text)
                .font(.theme(Typography.IOS.footnote).monospacedDigit())
                .foregroundStyle(Color(ThemeColor.labelSecondary))
        }

        private func timing(_ text: String) -> some View {
            Text(text)
                .font(.theme(Typography.IOS.footnote))
                .foregroundStyle(Color(ThemeColor.labelTertiary))
        }

        private var statusColor: Color {
            switch row.status {
            case .notStarted: Color(ThemeColor.labelSecondary)
            case .nothingSpent, .noCategories: Color(ThemeColor.labelTertiary)
            case .onTrack: Color(ThemeColor.labelPrimary)
            case .nearLimit: Color(ThemeColor.statusWarning)
            case .overspent: Color(ThemeColor.statusOverspent)
            }
        }

        private var barColor: Color {
            switch row.status {
            case .nearLimit: Color(ThemeColor.statusWarning)
            case .overspent: Color(ThemeColor.destructiveDefault)
            default: Color(ThemeColor.accentDefault)
            }
        }
    }
#endif
