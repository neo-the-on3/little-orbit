#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The state for the transaction entry sheet. Its view model is made once, when the sheet is requested.
    struct TransactionFormSheet: Identifiable {
        let id = UUID()
        let model: TransactionFormViewModel
    }

    /// The refund sheet for one expense, iOS and macOS ⌘R (D65), with its view model made when it's requested.
    struct RefundSheet: Identifiable {
        let id = UUID()
        let model: RefundFormViewModel
    }

    /// The macOS bulk edit sheet, with its view model made when the sheet is requested.
    struct BulkEditSheet: Identifiable {
        let id = UUID()
        let model: BulkEditViewModel
    }

    /// One account: the header, then its history (#23). iOS shows a grouped list (Figma 25:501) and macOS a
    /// table with multi-select (Figma 28:1343). Changes go into this window's undo history (#93, D187.2).
    struct AccountDetailView: View {
        let row: AccountRowModel
        let transactions: TransactionsFeature
        let onEdit: () -> Void
        /// Called after the ledger changes, so the account list refreshes its balances.
        let onChange: () -> Void
        @State private var history: AccountHistoryViewModel
        @State private var formSheet: TransactionFormSheet?
        @State private var bulkEditSheet: BulkEditSheet?
        @State private var refundSheet: RefundSheet?
        /// The step of the delete toast this screen showed.
        @State private var toastStepID: UUID?
        #if os(iOS)
            @State private var editMode: EditMode = .inactive
            /// Compact width (iPhone): the toolbar has Undo and + only, and Redo is in More (UI Designer, Figma).
            @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        #endif
        @Environment(WindowUndoHistory.self) private var undoHistory
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        init(
            row: AccountRowModel,
            transactions: TransactionsFeature,
            onEdit: @escaping () -> Void,
            onChange: @escaping () -> Void,
        ) {
            self.row = row
            self.transactions = transactions
            self.onEdit = onEdit
            self.onChange = onChange
            _history = State(initialValue: transactions.makeHistory(accountID: row.id))
        }

        var body: some View {
            content
                .navigationTitle(row.name)
                .toolbar { toolbar }
                .sheet(item: $formSheet) { sheet in
                    TransactionFormView(
                        model: sheet.model,
                        updates: transactions.updates,
                        onSaved: record,
                    )
                }
                .sheet(item: $refundSheet) { sheet in
                    RefundFormView(model: sheet.model, updates: transactions.updates, onSaved: record)
                }
                // Edit > Duplicate (⌘D) and Refund… (⌘R) work on the one selected row, on macOS and on iPad with
                // a hardware keyboard (D65, #31, S40).
                .focusedSceneValue(\.duplicateSelection, duplicateSelectionAction)
                .focusedSceneValue(\.refundSelection, refundSelectionAction)
                #if os(macOS)
                    .sheet(item: $bulkEditSheet) { sheet in
                        BulkEditView(
                            model: sheet.model,
                            updates: transactions.updates,
                            onApplied: record,
                        )
                    }
                #endif
                .bulkDeleteConfirmation(history.deletePrompt) { prompt in
                    // One Undo step for the whole selection, e.g. "Undo Delete 5 Transactions".
                    let message = history.toastMessage(deleting: Set(prompt.ids))
                    let figure = history.toastFigure(deleting: Set(prompt.ids))
                    if let change = history.confirmDelete() {
                        recordDelete(change, message: message, figure: figure)
                    }
                    onChange()
                } onCancel: {
                    history.cancelDelete()
                }
                .onChange(of: history.balanceText) { onChange() }
                // Any change to the shared store, from this window or another, reloads it (#87 B1, D187.4).
                .onChange(of: transactions.updates.revision) {
                    history.load()
                    onChange()
                }
                .task(id: row) { history.load() }
                // The toast and notice say where a change happened when it wasn't on this account (D165.1).
                .task(id: row.id) { undoHistory.setScreen(.account(row.id)) }
                // Leaving the list closes its toast (D164.2), but not the account delete toast that the
                // list it returns to shows (D170 U3).
                .onDisappear {
                    if let toast = undoHistory.toast, toast.stepID == toastStepID {
                        undoHistory.dismissToast()
                    }
                }
        }

        // MARK: - Actions

        /// Records a change in this window's history and refreshes. Adds and edits show no toast (D164.2).
        private func record(_ change: TransactionChange) {
            undoHistory.record(change)
            history.load()
            onChange()
        }

        /// Records a delete; on iOS and iPadOS the toast offers the same Undo step (D164.1, D164.2).
        private func recordDelete(_ change: TransactionChange, message: String, figure: String?) {
            let step = undoHistory.record(change)
            #if os(iOS)
                undoHistory.showToast(message, figure: figure, for: step)
                toastStepID = step
                editMode = .inactive
            #endif
        }

        private func delete(_ ids: Set<UUID>) {
            let message = history.toastMessage(deleting: ids)
            let figure = history.toastFigure(deleting: ids)
            if let change = history.requestDelete(ids: ids) {
                recordDelete(change, message: message, figure: figure)
                onChange()
            }
        }

        /// Undoes this window's newest step, whichever account it was on; the screen stays put (D162, D187.2).
        private func undo() {
            undoHistory.undo()
        }

        private func edit(_ ids: Set<UUID>) {
            if ids.count == 1, let id = ids.first {
                formSheet = TransactionFormSheet(model: transactions.makeForm(.edit(id)))
            } else if ids.count > 1 {
                let order = history.allRows.map(\.id)
                bulkEditSheet = BulkEditSheet(model: transactions.makeBulkEdit(order.filter { ids.contains($0) }))
            }
        }

        private func refund(_ id: UUID) {
            refundSheet = RefundSheet(model: transactions.makeRefund(of: id))
        }

        /// Copies one row as one Undo step (D65, D221, S29). Adds show no toast (D164.2).
        private func duplicate(_ id: UUID) {
            if let change = history.duplicate(id: id) {
                record(change)
            }
        }

        /// Edit > Duplicate for the selection: available on one row, hidden on one refund, else `nil`, which
        /// disables ⌘D.
        private var duplicateSelectionAction: DuplicateCommand? {
            if let id = history.duplicateTarget(history.selection) {
                return .available(SelectionAction { duplicate(id) })
            }
            let selection = history.selection
            return selection.count == 1 && history.refundIDs.isSuperset(of: selection) ? .hidden : nil
        }

        /// Refund for the selection, or `nil` when it isn't exactly one expense, which disables ⌘R.
        private var refundSelectionAction: SelectionAction? {
            history.refundTarget(history.selection).map { id in SelectionAction { refund(id) } }
        }

        // MARK: - Content

        @ViewBuilder private var content: some View {
            #if os(macOS)
                if history.isEmpty {
                    // #82 B9: when the header and empty state are taller than the window, the detail scrolls
                    // instead of compressing the header. When everything fits, the empty state stays centred.
                    ViewThatFits(in: .vertical) {
                        emptyContent(fillsHeight: true)
                        ScrollView {
                            emptyContent(fillsHeight: false)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: Spacing.space3) {
                        header
                        AccountTransactionsTable(
                            history: history,
                            onEdit: edit,
                            onDuplicate: duplicate,
                            onRefund: refund,
                            onDelete: delete,
                        )
                        Text(history.selectionSummary ?? " ")
                            .font(.theme(Typography.MacOS.footnote))
                            .foregroundStyle(Color(ThemeColor.labelSecondary))
                    }
                    .padding(Layout.marginMacOS)
                }
            #else
                List(selection: $history.selection) {
                    Section { header }
                    if history.isEmpty {
                        Section { emptyState }
                    }
                    if !history.upcoming.isEmpty {
                        Section {
                            ForEach(history.upcoming) { rowButton($0) }
                        } header: {
                            sectionHeader("Upcoming", trailing: history.upcomingTotalText, tone: .negative)
                        }
                    }
                    ForEach(history.sections) { section in
                        Section {
                            ForEach(section.rows) { rowButton($0) }
                        } header: {
                            sectionHeader(section.title, trailing: section.netChangeText, tone: section.netChangeTone)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                // iPadOS and iOS multi-select: Select, pick rows, then Delete (D161.2).
                .environment(\.editMode, $editMode)
                .toolbar(editMode.isEditing ? .visible : .hidden, for: .bottomBar)
                // Above the bottom safe area, so the list scrolls clear of it (D164.2).
                .safeAreaInset(edge: .bottom) {
                    if let toast = undoHistory.toast {
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
            #endif
        }

        #if os(macOS)
            private func emptyContent(fillsHeight: Bool) -> some View {
                VStack(alignment: .leading, spacing: Spacing.space3) {
                    header
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil)
                }
                .padding(Layout.marginMacOS)
            }
        #endif

        /// Figma 25:501 header: "Current balance", the amount, then "After upcoming" when there is any.
        private var header: some View {
            VStack(alignment: Self.headerAlignment, spacing: Spacing.space1) {
                Text(Self.balanceLabel(row))
                    .font(.theme(Self.captionStyle))
                    .foregroundStyle(Color(ThemeColor.labelSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                Text(history.balanceText)
                    .font(.theme(Self.amountStyle))
                    .foregroundStyle(history.balanceTone.color)
                    .lineLimit(1)
                    // Full style, never smaller than the caption; scales only when the number alone is wider
                    // than the screen: to 0.8 at most, or 0.5 at accessibility sizes so it never truncates
                    // (UI Designer, #82 U4).
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.5 : 0.8)
                    // Its height is fixed, so a short screen can't shrink it vertically (#82 B9).
                    .fixedSize(horizontal: false, vertical: true)
                if let after = history.afterUpcomingText {
                    Text(after)
                        .font(.theme(Self.captionStyle))
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                // The captions and over-limit line wrap and never truncate (#82 B2, U4).
                if let warning = row.warning {
                    Text(warning)
                        .font(.theme(Self.captionStyle))
                        .foregroundStyle(Color(ThemeColor.statusOverspent))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: Self.headerFrameAlignment)
            .accessibilityElement(children: .combine)
        }

        private var emptyState: some View {
            // D114: shown until the account has its first transaction, on either side of a transfer.
            ContentUnavailableView {
                Label {
                    Text("No transactions yet")
                } icon: {
                    // Decorative (Tester's #87 B3).
                    Image(systemName: "tray")
                        .accessibilityHidden(true)
                }
            } description: {
                Text("Add one with +. Transactions for this account will show here.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        #if os(iOS)
            /// While selecting, the row is plain so a tap selects it, as the List does; otherwise a tap edits
            /// (Tester's #87 recheck, bug 4).
            @ViewBuilder
            private func rowButton(_ row: TransactionRowModel) -> some View {
                if editMode.isEditing {
                    TransactionRowView(row: row)
                        .deleteDisabled(true)
                } else {
                    editableRow(row)
                }
            }

            /// The swipe is Refund · Duplicate · Delete by the row (D117.2), with no `onDelete` beside it, so
            /// VoiceOver lists Delete once (Tester's #87 recheck). The long-press menu is Edit, Duplicate, Refund…,
            /// then Delete last; a refund shows no Duplicate or Refund… (UI Designer, 23 Oct).
            private func editableRow(_ row: TransactionRowModel) -> some View {
                Button {
                    formSheet = TransactionFormSheet(model: transactions.makeForm(.edit(row.id)))
                } label: {
                    TransactionRowView(row: row)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the transaction to edit")
                .modifier(
                    TransactionSwipeActions(
                        offersRefund: history.refundableIDs.contains(row.id),
                        offersDuplicate: !history.refundIDs.contains(row.id),
                        onRefund: { refund(row.id) },
                        onDuplicate: { duplicate(row.id) },
                        onDelete: { delete([row.id]) },
                    )
                )
                .contextMenu {
                    TransactionRowMenu(
                        offersDuplicate: !history.refundIDs.contains(row.id),
                        offersRefund: history.refundableIDs.contains(row.id),
                        onEdit: { formSheet = TransactionFormSheet(model: transactions.makeForm(.edit(row.id))) },
                        onDuplicate: { duplicate(row.id) },
                        onRefund: { refund(row.id) },
                        onDelete: { delete([row.id]) },
                    )
                }
            }

            private func sectionHeader(_ title: String, trailing: String?, tone: AmountTone) -> some View {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(title)
                        Spacer()
                        trailing.map { Text($0).foregroundStyle(tone.color) }
                    }
                    VStack(alignment: .leading) {
                        Text(title)
                        trailing.map { Text($0).foregroundStyle(tone.color) }
                    }
                }
                .font(.theme(Typography.IOS.footnoteEmphasized))
            }
        #endif

        // MARK: - Toolbar

        /// "Undo Delete Transaction in Household Card", as in the Edit menu and the shake alert (D198).
        private var undoButtonTitle: String {
            undoHistory.undoTitle.map { "Undo \($0)" } ?? "Undo"
        }

        private var undoButton: some View {
            Button(action: undo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .accessibilityLabel(undoButtonTitle)
            .help(undoButtonTitle)
            .disabled(!undoHistory.canUndo)
        }

        /// "Redo Delete Transaction": the user's action, after an Undo from here or the toast (D164.2).
        private var redoButtonTitle: String {
            undoHistory.redoTitle.map { "Redo \($0)" } ?? "Redo"
        }

        private var redoButton: some View {
            Button {
                undoHistory.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .accessibilityLabel(redoButtonTitle)
            .help(redoButtonTitle)
            .disabled(!undoHistory.canRedo)
        }

        @ToolbarContentBuilder private var toolbar: some ToolbarContent {
            #if os(macOS)
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        formSheet = TransactionFormSheet(model: transactions.makeForm(.new(accountID: row.id)))
                    } label: {
                        Label("New Transaction", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .help("New Transaction (⌘N)")
                    Button {
                        edit(history.selection)
                    } label: {
                        Label("Edit Transactions…", systemImage: "pencil")
                    }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(history.selection.isEmpty)
                    .help("Edit the selected transactions (⌘E)")
                    Button("Edit Account", action: onEdit)
                }
                ToolbarItemGroup(placement: .navigation) {
                    undoButton
                    redoButton
                }
            #else
                ToolbarItemGroup(placement: .primaryAction) {
                    undoButton
                    if horizontalSizeClass != .compact {
                        redoButton
                    }
                    Button {
                        formSheet = TransactionFormSheet(model: transactions.makeForm(.new(accountID: row.id)))
                    } label: {
                        Label("Add Transaction", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    Menu {
                        if horizontalSizeClass == .compact {
                            // Shake still offers Redo too (D164.2).
                            Button(redoButtonTitle, systemImage: "arrow.uturn.forward") { undoHistory.redo() }
                                .disabled(!undoHistory.canRedo)
                        }
                        Button(
                            editMode.isEditing ? "Done Selecting" : "Select Transactions",
                            systemImage: "checkmark.circle",
                        ) {
                            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                        }
                        .disabled(history.isEmpty)
                        Button("Edit Account", systemImage: "pencil", action: onEdit)
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Done") { withAnimation { editMode = .inactive } }
                    Spacer()
                    Button("Delete", role: .destructive) { delete(history.selection) }
                        .disabled(history.selection.isEmpty)
                }
            #endif
        }

        private static func balanceLabel(_ row: AccountRowModel) -> String {
            #if os(macOS)
                row.detailCaption
            #else
                "Current balance"
            #endif
        }

        #if os(macOS)
            private static let captionStyle = Typography.MacOS.footnote
            private static let amountStyle = Typography.Amount.macOSTitle
            private static let headerAlignment = HorizontalAlignment.leading
            private static let headerFrameAlignment = Alignment.leading
        #else
            private static let captionStyle = Typography.IOS.footnote
            private static let amountStyle = Typography.Amount.iOSTitle
            private static let headerAlignment = HorizontalAlignment.center
            private static let headerFrameAlignment = Alignment.center
        #endif
    }
#endif
