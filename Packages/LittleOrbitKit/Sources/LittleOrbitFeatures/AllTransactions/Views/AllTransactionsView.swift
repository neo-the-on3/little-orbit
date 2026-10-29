#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The Mac detail column for the sidebar's All Transactions (#243, D421). It opens the register's editor, Bulk
    /// Edit and delete confirmation, and records every change in this window's undo history as the register does.
    struct AllTransactionsView: View {
        let transactions: TransactionsFeature
        /// Called after the ledger changes, so the sidebar refreshes its balances.
        let onChange: () -> Void
        @State private var model: AllTransactionsViewModel
        @State private var formSheet: TransactionFormSheet?
        @State private var bulkEditSheet: BulkEditSheet?
        @Environment(WindowUndoHistory.self) private var undoHistory

        init(transactions: TransactionsFeature, onChange: @escaping () -> Void) {
            self.transactions = transactions
            self.onChange = onChange
            _model = State(initialValue: AllTransactionsViewModel(useCases: transactions.useCases))
        }

        var body: some View {
            content
                .navigationTitle("All Transactions")
                .toolbar { toolbar }
                .sheet(item: $formSheet) { sheet in
                    TransactionFormView(model: sheet.model, onSaved: record)
                        .openSheet(hasUnsavedEdits: { sheet.model.hasUnsavedEdits }, close: { formSheet = nil })
                }
                .sheet(item: $bulkEditSheet) { sheet in
                    BulkEditView(model: sheet.model, onApplied: record)
                        .openSheet(hasUnsavedEdits: { sheet.model.hasUnsavedEdits }, close: { bulkEditSheet = nil })
                }
                .bulkDeleteConfirmation(model.deletePrompt) { _ in
                    if let change = model.confirmDelete() {
                        record(change)
                    }
                    onChange()
                } onCancel: {
                    model.cancelDelete()
                }
                // Any change to the shared store, from this window or another, refreshes it (D187.4). A registered
                // list's refresh starts as the change is posted, so this only catches what doesn't start one, such as
                // a restore (#341).
                .onChange(of: transactions.updates.revision) {
                    Task { await model.refresh(after: transactions.updates) }
                }
                .onChange(of: model.visibleIDs) { undoHistory.setScreen(.list(visible: model.visibleIDs)) }
                .task {
                    // Registers it, and loads it off the main actor (#341).
                    await model.appeared(in: transactions.updates)
                    undoHistory.setScreen(.list(visible: model.visibleIDs))
                }
                .onDisappear {
                    model.disappeared(from: transactions.updates)
                }
        }

        // MARK: - Actions

        private func record(_ change: TransactionChange) {
            undoHistory.record(change)
        }

        private func edit(_ ids: Set<UUID>) {
            switch model.editTarget(for: ids) {
            case .transaction(let id):
                formSheet = TransactionFormSheet(model: transactions.makeForm(.edit(id)))
            case .bulkEdit(let ordered):
                bulkEditSheet = BulkEditSheet(model: transactions.makeBulkEdit(ordered))
            case nil:
                break
            }
        }

        private func delete(_ ids: Set<UUID>) {
            if let change = model.requestDelete(ids: ids) {
                record(change)
                onChange()
            }
        }

        // MARK: - Content

        @ViewBuilder private var content: some View {
            if model.hasLoaded, model.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text(model.emptyTitle)
                    } icon: {
                        Image(systemName: "tray")
                            .accessibilityHidden(true)
                    }
                } description: {
                    Text(model.emptyMessage)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: Spacing.space3) {
                    AllTransactionsTable(model: model, onEdit: edit, onDelete: delete)
                    Text(model.selectionSummary ?? " ")
                        .font(.theme(Typography.MacOS.footnote))
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                }
                .padding(Layout.marginMacOS)
            }
        }

        // MARK: - Toolbar

        private var undoButtonTitle: String {
            undoHistory.undoTitle.map { "Undo \($0)" } ?? "Undo"
        }

        private var redoButtonTitle: String {
            undoHistory.redoTitle.map { "Redo \($0)" } ?? "Redo"
        }

        @ToolbarContentBuilder private var toolbar: some ToolbarContent {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    // The form's usual default: the last used account (D421.8).
                    formSheet = TransactionFormSheet(model: transactions.makeForm(.new(accountID: nil)))
                } label: {
                    Label("New Transaction", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("New Transaction (⌘N)")
                Button {
                    edit(model.selection)
                } label: {
                    Label("Edit Transactions…", systemImage: "pencil")
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(model.selection.isEmpty || transactions.updates.isBatchRunning)
                .help("Edit the selected transactions (⌘E)")
            }
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    undoHistory.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .accessibilityLabel(undoButtonTitle)
                .help(undoButtonTitle)
                .disabled(!undoHistory.canUndo)
                Button {
                    undoHistory.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .accessibilityLabel(redoButtonTitle)
                .help(redoButtonTitle)
                .disabled(!undoHistory.canRedo)
            }
        }
    }
#endif
