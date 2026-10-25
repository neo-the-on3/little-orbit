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
        /// This window's own pending Delete Account prompt; never on the shared model (#87 B3).
        @State private var deleteConfirmation: AccountDeleteConfirmation
        /// This window's undo history; a new window starts with an empty one, and closing it drops it (D187.8).
        @State private var undoSlot = WindowUndoSlot()
        private let feature: AccountsFeature
        private let transactions: TransactionsFeature
        /// The Scheduled screens (#26); without them the sidebar row shows its placeholder.
        private let scheduled: ScheduledFeature?

        private var undoHistory: WindowUndoHistory {
            undoSlot.history(from: transactions)
        }

        /// Both features come from the composition root, which built them once with the injected use cases.
        public init(feature: AccountsFeature, transactions: TransactionsFeature, scheduled: ScheduledFeature? = nil) {
            self.feature = feature
            self.transactions = transactions
            self.scheduled = scheduled
            _model = State(initialValue: feature.accounts)
            _deleteConfirmation = State(initialValue: AccountDeleteConfirmation(model: feature.accounts))
        }

        /// After an account delete: the selection leaves it, and the step goes into this window's history (#93,
        /// D187.9). macOS
        /// shows no toast (D164.1); the Edit menu has the Undo.
        private func deleted(_ change: TransactionChange) {
            if let id = change.accountIDs.first, selection == .account(id) {
                selection = .allTransactions
            }
            undoHistory.record(change)
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
                    onDelete: { deleteConfirmation.request(accountID: $0) },
                )
                // Delete Account… confirms over the sheet, as on iPad (Tester's #87 recheck).
                .accountDeleteAlert(deleteConfirmation, model: model, onHidden: { formSheet = nil }) { _, change in
                    formSheet = nil
                    deleted(change)
                }
            }
            // From the sidebar's context menu; the edit sheet shows its own.
            .accountDeleteAlert(deleteConfirmation, model: model, isActive: formSheet == nil) { _, change in
                deleted(change)
            }
            .task { model.load() }
            // Balances follow any change to the shared store, from any window (#87 B1, D187.4).
            .onChange(of: transactions.updates.revision) { model.load() }
            // A screen that isn't one account shows no transactions yet, so the toast and notice say where (D165.1).
            .onChange(of: selection, initial: true) {
                if case .account = selection {
                    return
                }
                undoHistory.setScreen(.list(visible: []))
            }
            // This window's own history; Show on the off-screen notice selects the account (D164.3).
            .undoWindow(undoHistory) { selection = .account($0) }
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
            Button("Delete Account…", role: .destructive) { deleteConfirmation.request(accountID: row.id) }
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
                    AccountDetailView(
                        row: row,
                        transactions: transactions,
                        scheduled: scheduled,
                        onEdit: { formSheet = AccountFormSheet(model: feature.makeForm(.edit(id))) },
                        onChange: { model.load() },
                    )
                    .id(id)
                } else {
                    noSelection
                }
            case .home(.scheduled) where scheduled != nil:
                if let scheduled {
                    // Its own stack, so a row opens the item in the detail column.
                    NavigationStack {
                        ScheduledListView(feature: scheduled)
                    }
                }
            case .home(let destination):
                UpcomingFeatureView(
                    title: destination.title,
                    systemImage: destination.symbolName,
                    message: destination.emptyText,
                )
            case .scheduled:
                // Only the iPhone and iPad stack pushes it; here the list has its own stack.
                noSelection
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
