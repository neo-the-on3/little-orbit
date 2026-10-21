#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The iOS home screen: Budgets, Scheduled and Reports, net wealth, then Assets and Credit
    /// (Figma 14:1424 first run and populated, 14:1842 reorder). The Edit button only reorders (D151).
    public struct AccountsHomeView: View {
        @State private var model: AccountsViewModel
        @State private var formSheet: AccountFormSheet?
        @State private var transactionAccount: AccountRowModel?
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        private let feature: AccountsFeature

        /// `feature` comes from the composition root, which built it once with the injected use cases.
        public init(feature: AccountsFeature) {
            self.feature = feature
            _model = State(initialValue: feature.accounts)
        }

        public var body: some View {
            NavigationStack {
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
            }
            .sheet(item: $formSheet) { sheet in
                AccountFormView(
                    model: sheet.model,
                    onSaved: { _ in model.load() },
                    onDelete: { model.requestDelete(accountID: $0) },
                )
            }
            .sheet(item: $transactionAccount) { row in
                NavigationStack {
                    UpcomingFeatureView(
                        title: "New Transaction",
                        systemImage: "plus.circle",
                        message: "Adding a transaction to \(row.name) arrives with the transaction entry sheet.",
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { transactionAccount = nil }
                        }
                    }
                }
            }
            .alert(
                model.deletePrompt?.title ?? "",
                isPresented: Binding(get: { model.deletePrompt != nil }, set: { _ in }),
                presenting: model.deletePrompt,
            ) { prompt in
                Button(prompt.hideTitle) { model.hideInsteadOfDeleting() }
                Button(prompt.deleteTitle, role: .destructive) { model.confirmDelete() }
                Button(prompt.cancelTitle, role: .cancel) { model.cancelDelete() }
            } message: { prompt in
                Text(prompt.message)
            }
            .task { model.load() }
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
                                    transactionAccount = row
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
                transactionAccount = row
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
                model.requestDelete(accountID: row.id)
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
                        onEdit: { formSheet = AccountFormSheet(model: feature.makeForm(.edit(id))) },
                    )
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
