#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The iOS home screen: Budgets, Scheduled and Reports, net wealth, then Assets and Credit
    /// (Figma 14:1424 first run and populated, 14:1842 reorder). The Edit button only reorders (D151).
    public struct AccountsHomeView: View {
        @State private var model: AccountsViewModel
        @State private var formSheet: AccountFormSheet?
        /// This window's own pending Delete Account prompt; never on the shared model (#87 B3).
        @State private var deleteConfirmation: AccountDeleteConfirmation
        @State private var transactionSheet: TransactionFormSheet?
        /// Show on the off-screen undo notice pushes an account (D164.3); nothing else navigates for undo.
        @State private var path: [AccountsRoute] = []
        /// This window's undo history; a new window starts with an empty one, and closing it drops it (D187.8).
        @State private var undoSlot = WindowUndoSlot()
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        private let feature: AccountsFeature
        private let transactions: TransactionsFeature

        private var undoHistory: WindowUndoHistory {
            undoSlot.history(from: transactions)
        }

        /// Both features come from the composition root, which built them once with the injected use cases.
        public init(feature: AccountsFeature, transactions: TransactionsFeature) {
            self.feature = feature
            self.transactions = transactions
            _model = State(initialValue: feature.accounts)
            _deleteConfirmation = State(initialValue: AccountDeleteConfirmation(model: feature.accounts))
        }

        /// After an account delete: its page closes, back to the list, and the list shows the D164 toast with
        /// Undo, which restores the account and its transactions in one step (UI Designer's D170, U3).
        private func deleted(_ name: String, _ change: TransactionChange) {
            path.removeAll { $0 == .account(change.accountIDs.first ?? UUID()) }
            let step = undoHistory.record(change)
            undoHistory.showToast(UndoToast.message(deletedAccount: name), for: step)
        }

        public var body: some View {
            NavigationStack(path: $path) {
                List {
                    homeSection
                    if model.isFirstRun {
                        firstRunSection
                    } else {
                        netWealthSection
                        accountSection(.assets)
                        accountSection(.credit)
                        hiddenSection
                    }
                }
                .listStyle(.insetGrouped)
                // One reorder state from the view model drives both the List and the toolbar's
                // Edit/Done button (Tester bug 1: an EditButton in the toolbar sat outside this override).
                .environment(\.editMode, reorderMode)
                .navigationTitle("Accounts")
                .toolbar { toolbar }
                .navigationDestination(for: AccountsRoute.self) { destination(for: $0) }
                // The home list isn't one account and shows no transactions, so the toast and notice say where (D165.1).
                .onAppear { undoHistory.setScreen(.list(visible: [])) }
                // Back from an account on iPhone, the list is on screen again (D187.3).
                .onChange(of: path) {
                    if path.isEmpty {
                        undoHistory.setScreen(.list(visible: []))
                    }
                }
                // The account delete toast, above the bottom safe area (D164.2, D170 U3).
                .safeAreaInset(edge: .bottom) {
                    if let toast = undoHistory.toast, path.isEmpty {
                        UndoToastView(
                            toast: toast,
                            onUndo: { undoHistory.undoToast() },
                            onTimeout: { undoHistory.dismissToast() },
                        )
                        .padding(.bottom, Spacing.space2)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.default, value: undoHistory.toast)
            }
            .undoWindow(undoHistory) { path = [.account($0)] }
            .sheet(item: $formSheet) { sheet in
                AccountFormView(
                    model: sheet.model,
                    onSaved: { _ in model.load() },
                    onDelete: { deleteConfirmation.request(accountID: $0) },
                )
                // Delete Account… confirms over the sheet (Tester's #87 recheck, bug 3).
                .accountDeleteAlert(deleteConfirmation, model: model, onHidden: { formSheet = nil }) { name, change in
                    formSheet = nil
                    deleted(name, change)
                }
            }
            .sheet(item: $transactionSheet) { sheet in
                // #23: the entry sheet, opened from a row's swipe or context menu.
                TransactionFormView(
                    model: sheet.model,
                    onSaved: { change in
                        undoHistory.record(change)
                        model.load()
                    },
                )
            }
            // From a row's context menu or swipe; the edit sheet shows its own (bug 3).
            .accountDeleteAlert(deleteConfirmation, model: model, isActive: formSheet == nil, onDeleted: deleted)
            .task { model.load() }
            // Balances follow any change to the shared store, from any window (#87 B1, D187.4).
            .onChange(of: transactions.updates.revision) { model.load() }
        }

        // MARK: - Sections

        private var homeSection: some View {
            Section {
                ForEach(model.homeRows) { row in
                    NavigationLink(value: AccountsRoute.home(row.destination)) {
                        HomeRowView(row: row)
                    }
                }
            }
        }

        private var firstRunSection: some View {
            Section {
                VStack(spacing: Spacing.space3) {
                    Image(systemName: "building.columns")
                        .font(.system(size: 40))
                        .foregroundStyle(Color(ThemeColor.accentDefault))
                        .accessibilityHidden(true)
                    Text("Add your first account")
                        .font(.theme(Typography.IOS.title3))
                    Text("Start with the account you use most. You can add the rest later.")
                        .font(.theme(Typography.IOS.subheadline))
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                        .multilineTextAlignment(.center)
                    Button {
                        formSheet = AccountFormSheet(model: feature.makeForm(.firstAccount))
                    } label: {
                        // label/on-accent keeps contrast on accent/default in dark mode (Tester bug 4).
                        Text("Add Account")
                            .font(.theme(Typography.IOS.bodyEmphasized))
                            .foregroundStyle(Color(ThemeColor.labelOnAccent))
                            .padding(.horizontal, Spacing.space5)
                            .frame(minHeight: Layout.minimumTargetIOS)
                            .background(Color(ThemeColor.accentDefault), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.space6)
            }
        }

        private var netWealthSection: some View {
            Section {
                NavigationLink(value: AccountsRoute.allTransactions) {
                    VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                        Text("All Accounts")
                            .font(.theme(Typography.IOS.footnote))
                            .foregroundStyle(Color(ThemeColor.labelSecondary))
                        ForEach(model.netWealth) { line in
                            // One line, never split, minus sign attached; scales only at AX sizes (#82 B7).
                            Text(line.text)
                                .font(.theme(Typography.Amount.iOSTitle))
                                .foregroundStyle(Color(ThemeColor.labelPrimary))
                                .lineLimit(1)
                                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.5 : 1)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.allAccountsAccessibilityLabel)
                }
            }
        }

        @ViewBuilder
        private func accountSection(_ group: AccountGroup) -> some View {
            let rows = model.rows(in: group)
            if !rows.isEmpty {
                Section(group.title) {
                    ForEach(rows) { row in
                        NavigationLink(value: AccountsRoute.account(row.id)) {
                            AccountRowView(row: row)
                        }
                        .swipeActions(edge: .leading) {
                            if model.allowsRowActions {
                                Button {
                                    transactionSheet = TransactionFormSheet(
                                        model: transactions.makeForm(.new(accountID: row.id))
                                    )
                                } label: {
                                    Label("Add Transaction", systemImage: "plus")
                                }
                                .tint(Color(ThemeColor.accentDefault))
                            }
                        }
                        .contextMenu {
                            if model.allowsRowActions {
                                menu(for: row)
                            }
                        }
                    }
                    .onMove { model.move(in: group, fromOffsets: $0, toOffset: $1) }
                    // D151: Edit mode only reorders, so rows never get delete controls.
                    .deleteDisabled(true)
                }
            }
        }

        @ViewBuilder private var hiddenSection: some View {
            if model.hiddenCount > 0 {
                Section {
                    Toggle(model.showHiddenTitle, isOn: $model.showHidden)
                }
            }
        }

        @ViewBuilder
        private func menu(for row: AccountRowModel) -> some View {
            Button {
                formSheet = AccountFormSheet(model: feature.makeForm(.edit(row.id)))
            } label: {
                Label("Edit Account", systemImage: "pencil")
            }
            Button {
                transactionSheet = TransactionFormSheet(model: transactions.makeForm(.new(accountID: row.id)))
            } label: {
                Label("Add Transaction", systemImage: "plus")
            }
            Button {
                model.setHidden(!row.isHidden, accountID: row.id)
            } label: {
                Label(
                    row.isHidden ? "Unhide Account" : "Hide Account",
                    systemImage: row.isHidden ? "eye" : "eye.slash",
                )
            }
            Button {
                model.setExcluded(!row.isExcluded, accountID: row.id)
            } label: {
                Label(
                    row.isExcluded ? "Include in Net Wealth" : "Exclude from Net Wealth",
                    systemImage: "sum",
                )
            }
            Divider()
            Button(role: .destructive) {
                deleteConfirmation.request(accountID: row.id)
            } label: {
                Label("Delete Account…", systemImage: "trash")
            }
        }

        @ToolbarContentBuilder private var toolbar: some ToolbarContent {
            if !model.isFirstRun {
                ToolbarItem(placement: .topBarLeading) {
                    Button(model.isReordering ? "Done" : "Edit") {
                        withAnimation { model.isReordering.toggle() }
                    }
                    .fontWeight(model.isReordering ? .semibold : .regular)
                }
            }
            if model.allowsRowActions {
                ToolbarItem(placement: .topBarTrailing) {
                    addButton
                }
            }
        }

        private var addButton: some View {
            Button {
                formSheet = AccountFormSheet(model: feature.makeForm(model.isFirstRun ? .firstAccount : .new))
            } label: {
                Label("Add Account", systemImage: "plus")
            }
        }

        /// The List's edit mode mirrors the view model's reorder state (D151): Edit enters it, Done leaves it.
        private var reorderMode: Binding<EditMode> {
            Binding(
                get: { model.isReordering ? .active : .inactive },
                set: { model.isReordering = $0.isEditing },
            )
        }

        @ViewBuilder
        private func destination(for route: AccountsRoute) -> some View {
            switch route {
            case .allTransactions:
                UpcomingFeatureView(
                    title: "All Transactions",
                    systemImage: "list.bullet",
                    message: "The transaction list arrives with its own issue.",
                )
            case .home(let destination):
                UpcomingFeatureView(
                    title: destination.title,
                    systemImage: destination.symbolName,
                    message: destination.emptyText,
                )
            case .account(let id):
                if let row = model.row(id: id) {
                    AccountDetailView(
                        row: row,
                        transactions: transactions,
                        onEdit: { formSheet = AccountFormSheet(model: feature.makeForm(.edit(id))) },
                        onChange: { model.load() },
                    )
                    .id(id)
                } else {
                    UpcomingFeatureView(
                        title: "Account",
                        systemImage: "questionmark",
                        message: "This account was deleted.",
                    )
                }
            }
        }
    }
#endif
