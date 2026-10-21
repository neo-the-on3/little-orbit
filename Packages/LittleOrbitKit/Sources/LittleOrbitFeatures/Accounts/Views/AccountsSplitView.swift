#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The macOS window: a sidebar with All Transactions, Budgets, Scheduled, Reports, then
    /// Accounts and Credit, and net wealth pinned to the bottom (Figma 14:1846).
    public struct AccountsSplitView: View {
        @State private var model: AccountsViewModel
        @State private var selection: AccountsRoute? = .allTransactions
        @State private var formSheet: AccountFormSheet?
        private let feature: AccountsFeature

        /// `feature` comes from the composition root, which built it once with the injected use cases.
        public init(feature: AccountsFeature) {
            self.feature = feature
            _model = State(initialValue: feature.accounts)
        }

        public var body: some View {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            } detail: {
                detail
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        formSheet = AccountFormSheet(model: feature.makeForm(model.isFirstRun ? .firstAccount : .new))
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                    .help("Add Account")
                }
            }
            .sheet(item: $formSheet) { sheet in
                AccountFormView(
                    model: sheet.model,
                    onSaved: { account in
                        model.load()
                        selection = .account(account.id)
                    },
                    onDelete: { model.requestDelete(accountID: $0) },
                )
            }
            .alert(
                model.deletePrompt?.title ?? "",
                isPresented: Binding(get: { model.deletePrompt != nil }, set: { _ in }),
                presenting: model.deletePrompt,
            ) { prompt in
                Button(prompt.hideTitle) { model.hideInsteadOfDeleting() }
                    .keyboardShortcut(.defaultAction)
                Button(prompt.deleteTitle, role: .destructive) {
                    if selection == .account(prompt.accountID) {
                        selection = .allTransactions
                    }
                    model.confirmDelete()
                }
                Button(prompt.cancelTitle, role: .cancel) { model.cancelDelete() }
            } message: { prompt in
                Text(prompt.message)
            }
            .task { model.load() }
        }

        // MARK: - Sidebar

        private var sidebar: some View {
            List(selection: $selection) {
                Label("All Transactions", systemImage: "list.bullet")
                    .tag(AccountsRoute.allTransactions)
                ForEach(model.homeRows) { row in
                    HStack {
                        Label(row.title, systemImage: row.symbolName)
                        Spacer()
                        if let badge = row.badge {
                            CountBadgeView(text: badge)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.accessibilityLabel)
                    .tag(AccountsRoute.home(row.destination))
                }
                if model.isFirstRun {
                    Section("Accounts") {
                        Button {
                            formSheet = AccountFormSheet(model: feature.makeForm(.firstAccount))
                        } label: {
                            Label("Add Account…", systemImage: "plus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color(ThemeColor.accentDefault))
                    }
                } else {
                    accountSection(.assets, title: "Accounts")
                    accountSection(.credit, title: AccountGroup.credit.title)
                    if model.hiddenCount > 0 {
                        Toggle(model.showHiddenTitle, isOn: $model.showHidden)
                            .toggleStyle(.checkbox)
                            .font(.theme(Typography.MacOS.footnote))
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) { netWealthFooter }
        }

        @ViewBuilder
        private func accountSection(_ group: AccountGroup, title: String) -> some View {
            let rows = model.rows(in: group)
            if !rows.isEmpty {
                Section(title) {
                    ForEach(rows) { row in
                        HStack {
                            Label(row.sidebarTitle, systemImage: row.symbolName)
                                .lineLimit(1)
                            Spacer()
                            // An amount is never truncated or split (UI Designer, #82).
                            Text(row.balanceText)
                                .font(.theme(Typography.Amount.macOSBody))
                                .foregroundStyle(row.balanceTone == .negative ? row.balanceTone.color : Color.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(row.accessibilityLabel)
                        .tag(AccountsRoute.account(row.id))
                        .contextMenu { menu(for: row) }
                    }
                    // D151: drag rows to reorder directly; macOS has no Edit mode.
                    .onMove { model.move(in: group, fromOffsets: $0, toOffset: $1) }
                }
            }
        }

        @ViewBuilder
        private func menu(for row: AccountRowModel) -> some View {
            Button("Edit Account…") { formSheet = AccountFormSheet(model: feature.makeForm(.edit(row.id))) }
            Button(row.isHidden ? "Unhide Account" : "Hide Account") {
                model.setHidden(!row.isHidden, accountID: row.id)
            }
            Button(row.isExcluded ? "Include in Net Wealth" : "Exclude from Net Wealth") {
                model.setExcluded(!row.isExcluded, accountID: row.id)
            }
            Divider()
            Button("Delete Account…", role: .destructive) { model.requestDelete(accountID: row.id) }
        }

        @ViewBuilder private var netWealthFooter: some View {
            if !model.isFirstRun {
                VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                    Text("Net wealth")
                        .font(.theme(Typography.MacOS.footnote))
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                    ForEach(model.netWealth) { line in
                        Text(line.text)
                            .font(.theme(Typography.Amount.macOSBody))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.space3)
                .background(.bar)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.netWealthSummary)
            }
        }

        // MARK: - Detail

        @ViewBuilder private var detail: some View {
            switch selection {
            case .account(let id):
                if let row = model.row(id: id) {
                    AccountDetailView(row: row) {
                        formSheet = AccountFormSheet(model: feature.makeForm(.edit(id)))
                    }
                } else {
                    noSelection
                }
            case .home(let destination):
                UpcomingFeatureView(
                    title: destination.title,
                    systemImage: destination.symbolName,
                    message: destination.emptyText,
                )
            case .allTransactions:
                if model.isFirstRun {
                    UpcomingFeatureView(
                        title: "Add your first account",
                        systemImage: "building.columns",
                        message: "Start with the account you use most. Use + or Add Account… in the sidebar.",
                    )
                } else {
                    UpcomingFeatureView(
                        title: "All Transactions",
                        systemImage: "list.bullet",
                        message: "The transaction list arrives with its own issue.",
                    )
                }
            case nil:
                noSelection
            }
        }

        private var noSelection: some View {
            UpcomingFeatureView(title: "No Selection", systemImage: "sidebar.left", message: "Pick an account.")
        }
    }
#endif
