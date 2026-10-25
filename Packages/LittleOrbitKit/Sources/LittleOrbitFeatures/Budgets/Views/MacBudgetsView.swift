#if canImport(SwiftUI) && os(macOS)
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The Mac Budgets screen (#25 part 5, Mac Budgets frames), in the window's detail column when the sidebar's
    /// Budgets row is picked. The list is a table: double-click or Open Budget shows the budget detail, and the
    /// right-click menu and the Budget menu have Edit Budget…, Change Budget Limit…, Duplicate, the periods and
    /// Delete Budget…. Every change is one step in the window's Undo history (D307.8), and both views reload
    /// after any ledger change (#25 AC 6).
    public struct MacBudgetsView: View {
        @State private var model: BudgetsViewModel
        @State private var selection: UUID?
        @State private var path: [UUID] = []
        /// The budget detail on show, kept here so the Budget menu acts on it.
        @State private var detail: BudgetDetailViewModel?
        @State private var form: MacBudgetFormSheet.Item?
        @State private var limit: BudgetDetailViewModel?
        @State private var deleting: BudgetDetailViewModel?
        @State private var alert: CategoryAlert?
        /// An alert from Change Budget Limit, shown once its sheet has closed (D309).
        @State private var pendingAlert: CategoryAlert?
        @State private var canCreate = false
        /// The window's Undo history (D307.8).
        @Environment(WindowUndoHistory.self) private var undoHistory: WindowUndoHistory?
        private let feature: BudgetsFeature

        public init(feature: BudgetsFeature) {
            self.feature = feature
            _model = State(initialValue: feature.makeList())
        }

        public var body: some View {
            NavigationStack(path: $path) {
                list
                    .navigationDestination(for: UUID.self) { id in
                        if let detail, detail.budgetID == id {
                            MacBudgetDetailView(model: detail, actions: actions(for: detail))
                        }
                    }
            }
            .sheet(item: $form) { item in
                MacBudgetFormSheet(item: item) { deleted(item.detail) }
            }
            .sheet(item: $limit, onDismiss: showPendingAlert) { model in
                MacBudgetLimitSheet(model: model) { alert in pendingAlert = alert }
            }
            .alert(
                deleting?.deleteTitle ?? "",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                presenting: deleting,
            ) { model in
                Button(CategoryText.delete, role: .destructive) { delete(model) }
                Button(CategoryText.cancel, role: .cancel) {}
            } message: { model in
                Text(model.deleteMessage)
            }
            .alert(
                alert?.title ?? "",
                isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } }),
                presenting: alert,
            ) { _ in
                Button(CategoryText.okay) { alert = nil }
            } message: { alert in
                Text(alert.message)
            }
            .focusedSceneValue(\.budgetMenu, menuActions)
            .onAppear { reload() }
            .onChange(of: feature.revision) { reload() }
            .onChange(of: path) {
                if path.isEmpty {
                    detail = nil
                }
            }
        }

        // MARK: List

        private var list: some View {
            Group {
                if model.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        table
                        Text(BudgetsViewModel.footnote)
                            .font(.theme(Typography.MacOS.footnote))
                            .foregroundStyle(Color(ThemeColor.labelSecondary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.space3)
                    }
                }
            }
            .navigationTitle(BudgetsViewModel.title)
            .navigationSubtitle(model.summaryText ?? "")
            .toolbar {
                if canCreate {
                    ToolbarItem(placement: .primaryAction) {
                        Button(BudgetText.newBudget, systemImage: "plus") { openForm(.new) }
                            .help(BudgetText.newBudget)
                    }
                }
            }
        }

        private var table: some View {
            Table(model.rows, selection: $selection) {
                TableColumn(BudgetText.budgetColumn) { row in
                    Text(row.name)
                        .help(row.name)
                }
                .width(min: 120, ideal: 180)
                TableColumn(BudgetText.progressColumn) { row in
                    if let progress = row.progress {
                        ProgressView(value: progress)
                            .tint(MacBudgetStyle.barColor(row.status))
                            .accessibilityHidden(true)
                    }
                }
                .width(min: 80, ideal: 120)
                TableColumn(BudgetText.spentColumn) { row in
                    Text(row.amountsText ?? "")
                        .font(.theme(Typography.Amount.macOSBody))
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                        .lineLimit(1)
                }
                .width(min: 140, ideal: 170)
                TableColumn(BudgetText.leftColumn) { row in
                    HStack(spacing: Spacing.space1) {
                        if let symbol = row.statusSymbol {
                            Image(systemName: symbol)
                        }
                        Text(row.statusText)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .foregroundStyle(MacBudgetStyle.statusColor(row.status))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.accessibilityLabel)
                }
                .width(min: 110, ideal: 140)
                TableColumn(BudgetText.periodColumn) { row in
                    Text(row.timingText ?? "")
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                        .lineLimit(1)
                }
                .width(min: 130, ideal: 170)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first, ids.count == 1, let row = model.rows.first(where: { $0.id == id }) {
                    rowMenu(row)
                }
            } primaryAction: { ids in
                if let id = ids.first, ids.count == 1 {
                    open(id)
                }
            }
            .onDeleteCommand {
                if let id = selection {
                    requestDelete(id)
                }
            }
        }

        /// The right-click menu, as the Mac Budgets right-click frame shows it, with the Budget menu's shortcuts.
        @ViewBuilder
        private func rowMenu(_ row: BudgetRow) -> some View {
            let menu = self.actions(for: row)
            Button(BudgetText.openBudget) { menu.open?() }
                .disabled(menu.open == nil)
            Button(BudgetText.editBudgetEllipsis) { menu.edit?() }
                .keyboardShortcut("e")
                .disabled(menu.edit == nil)
            Button(BudgetText.duplicate) { menu.duplicate?() }
                .disabled(menu.duplicate == nil)
            Divider()
            Button(BudgetText.showPreviousPeriod) { menu.showPrevious?() }
                .keyboardShortcut("[")
                .disabled(menu.showPrevious == nil)
            // The list always shows the current period, so there's no next one (Mac Budgets right-click frame).
            Button(BudgetText.showNextPeriod) {}
                .keyboardShortcut("]")
                .disabled(true)
            Divider()
            Button(BudgetText.deleteBudgetEllipsis, role: .destructive) { menu.delete?() }
                .keyboardShortcut(.delete)
                .disabled(menu.delete == nil)
        }

        @ViewBuilder private var emptyState: some View {
            ContentUnavailableView {
                Label(BudgetsViewModel.emptyTitle, systemImage: HomeDestination.budgets.symbolName)
            } description: {
                Text(BudgetsViewModel.emptyMessage)
            } actions: {
                if canCreate {
                    Button(BudgetText.newBudgetEllipsis) { openForm(.new) }
                }
            }
        }

        // MARK: Actions

        private var isPresenting: Bool {
            form != nil || limit != nil || deleting != nil || alert != nil
        }

        /// The Budget menu: the budget on show, otherwise the one picked in the list. Nothing while a sheet or
        /// an alert is up.
        private var menuActions: BudgetMenuActions {
            guard !isPresenting else {
                return BudgetMenuActions()
            }
            var actions: BudgetMenuActions
            if let detail, !path.isEmpty {
                actions = self.actions(for: detail)
            } else if let id = selection, let row = model.rows.first(where: { $0.id == id }) {
                actions = self.actions(for: row)
            } else {
                actions = BudgetMenuActions()
            }
            if canCreate {
                actions.newBudget = { openForm(.new) }
            }
            return actions
        }

        /// The actions for a list row. Those that need the budget's figures load its detail first, so they
        /// share the detail's rules and Undo steps (part 4).
        private func actions(for row: BudgetRow) -> BudgetMenuActions {
            let id = row.id
            let hasFigures = row.status != .noCategories
            var actions = BudgetMenuActions()
            guard feature.useCases.detail != nil else {
                return actions
            }
            actions.open = { open(id) }
            if feature.useCases.form != nil {
                actions.edit = { openForm(.edit(id), detail: loadedDetail(id)) }
            }
            if hasFigures {
                actions.changeLimit = {
                    if let model = loadedDetail(id) {
                        model.beginLimitChange()
                        limit = model
                    }
                }
                actions.duplicate = {
                    if let model = loadedDetail(id) {
                        duplicate(model)
                    }
                }
                actions.showPrevious = { open(id, atPreviousPeriod: true) }
            }
            actions.delete = { requestDelete(id) }
            return actions
        }

        /// The actions for the budget detail on show.
        private func actions(for model: BudgetDetailViewModel) -> BudgetMenuActions {
            var actions = BudgetMenuActions()
            guard model.state == .figures || model.state == .noCategories else {
                return actions
            }
            if feature.useCases.form != nil {
                actions.edit = { openForm(.edit(model.budgetID), detail: model) }
            }
            if model.state == .figures {
                actions.changeLimit = {
                    model.beginLimitChange()
                    limit = model
                }
            }
            if model.canDuplicate {
                actions.duplicate = { duplicate(model) }
            }
            if model.header?.canShowPrevious == true {
                actions.showPrevious = { model.showPreviousPeriod() }
            }
            if model.header?.canShowNext == true {
                actions.showNext = { model.showNextPeriod() }
            }
            if model.canShowCurrentPeriod {
                actions.showCurrent = { model.showCurrentPeriod() }
            }
            actions.delete = { deleting = model }
            return actions
        }

        private func reload() {
            model.load()
            canCreate = feature.canCreateBudget()
            detail?.load()
            if let id = selection, !model.rows.contains(where: { $0.id == id }) {
                selection = nil
            }
        }

        private func makeDetail(_ id: UUID) -> BudgetDetailViewModel? {
            let history = undoHistory
            return feature.makeDetail(id, history: { history })
        }

        /// The detail on show for this budget, or a new one, loaded.
        private func loadedDetail(_ id: UUID) -> BudgetDetailViewModel? {
            if let detail, detail.budgetID == id {
                return detail
            }
            guard let model = makeDetail(id) else {
                return nil
            }
            model.load()
            return model
        }

        private func open(_ id: UUID, atPreviousPeriod: Bool = false) {
            guard let model = makeDetail(id) else {
                return
            }
            model.load()
            if atPreviousPeriod {
                model.showPreviousPeriod()
            }
            selection = id
            detail = model
            path = [id]
        }

        private func openForm(_ mode: BudgetFormViewModel.Mode, detail: BudgetDetailViewModel? = nil) {
            let history = undoHistory
            do {
                form = MacBudgetFormSheet.Item(
                    form: try feature.makeForm(mode, history: { history }),
                    detail: detail,
                )
            } catch {
                alert = BudgetText.loadFailed
            }
        }

        /// Duplicate saves the copy at once and picks it in the list, as the Finder does (D307.6).
        private func duplicate(_ model: BudgetDetailViewModel) {
            if let copy = model.duplicate() {
                self.model.load()
                selection = copy
            } else {
                show(model)
            }
        }

        private func requestDelete(_ id: UUID) {
            if let model = loadedDetail(id) {
                deleting = model
            }
        }

        private func delete(_ model: BudgetDetailViewModel) {
            if model.delete() {
                deleted(model)
            } else {
                show(model)
            }
        }

        /// After a delete, here or from Edit Budget: back to the list, with nothing picked.
        private func deleted(_ model: BudgetDetailViewModel?) {
            if let model, detail?.budgetID == model.budgetID {
                path = []
            }
            selection = nil
            self.model.load()
        }

        /// Moves an alert from a budget's model, such as “This budget no longer exists.” (D309), to the screen.
        private func show(_ model: BudgetDetailViewModel) {
            if let modelAlert = model.alert {
                model.alert = nil
                alert = modelAlert
            }
        }

        private func showPendingAlert() {
            if let pendingAlert {
                self.pendingAlert = nil
                alert = pendingAlert
            }
        }
    }

    /// The budget status colours, as on iOS: tertiary when nothing's spent, the warning colour near the limit,
    /// and the overspent colour over it.
    enum MacBudgetStyle {
        static func statusColor(_ status: BudgetRow.Status) -> Color {
            switch status {
            case .notStarted: Color(ThemeColor.labelSecondary)
            case .nothingSpent, .noCategories: Color(ThemeColor.labelTertiary)
            case .onTrack: Color(ThemeColor.labelPrimary)
            case .nearLimit: Color(ThemeColor.statusWarning)
            case .overspent: Color(ThemeColor.statusOverspent)
            }
        }

        static func headlineColor(_ status: BudgetRow.Status) -> Color {
            switch status {
            case .nothingSpent, .noCategories: Color(ThemeColor.labelPrimary)
            default: statusColor(status)
            }
        }

        static func barColor(_ status: BudgetRow.Status) -> Color {
            switch status {
            case .nearLimit: Color(ThemeColor.statusWarning)
            case .overspent: Color(ThemeColor.destructiveDefault)
            default: Color(ThemeColor.accentDefault)
            }
        }
    }
#endif
