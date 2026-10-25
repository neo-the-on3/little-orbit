#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// The Scheduled list (#26 frames "Scheduled – overdue, due today, upcoming" on iOS and "Scheduled – overdue,
    /// due today, upcoming, completed; sidebar badge" on macOS, where it's `ScheduledTableView`). On iOS, after a
    /// catch-up recorded something while the app was closed, an info hint comes first. Overdue starts with its hint
    /// row, then lists each missed occurrence on its own row; then Due Today, Upcoming and a Completed row with its
    /// count. Rows are standard navigation links
    /// to the item; the context menu has Pay Now, Skip This Occurrence, Edit and Delete. It sits inside the caller's
    /// NavigationStack. Whichever Scheduled screen is on top presents the form, confirmations and alerts. A watch Pay
    /// or Skip the iPhone didn't apply shows as a card above everything else until OK (D374, D376).
    ///
    /// The Mac gives the list its own stack, and the list registers the item and Completed destinations. On iPhone
    /// and iPad it's pushed onto the Accounts stack, whose typed path only takes `AccountsRoute` and only honours
    /// its root's destinations, so the links push `linkValue(route)` and the root builds the pushed screens with the
    /// model from the host's slot, and buttons push through the host (Tester's #198 iOS FAIL).
    public struct ScheduledListView<Link: Hashable>: View {
        @State private var model: ScheduledListViewModel
        @Environment(WindowUndoHistory.self) private var undoHistory
        /// The item the Mac Table opened with Return or a double-click.
        @State private var openedItem: UUID?
        private let feature: ScheduledFeature
        /// Whether the list registers its own destinations or a parent stack builds them (with the slot and a way to
        /// push, always together).
        private let host: ScheduledListHost<Link>
        private let linkValue: (ScheduledRoute) -> Link

        /// A list that registers its own destinations (the Mac's detail column stack). A tapped reminder's item goes
        /// on that stack's path, which the window owns (S33).
        public init(feature: ScheduledFeature) where Link == ScheduledRoute {
            self.init(feature: feature, host: .ownStack, linkValue: { $0 })
        }

        /// A list whose links push `linkValue`'s values. On a parent stack (the iPhone and iPad Accounts stack) its
        /// root registers their destinations and builds them with the model in the host's slot. A tapped reminder's
        /// item goes on that stack's typed path, as a row tap pushes it (S33, Tech Architect 5660914450 B1).
        init(
            feature: ScheduledFeature,
            host: ScheduledListHost<Link>,
            linkValue: @escaping (ScheduledRoute) -> Link,
        ) {
            self.feature = feature
            self.host = host
            self.linkValue = linkValue
            // On a parent stack, the stack's one model, shared with the screens over the list (B2).
            _model = State(initialValue: host.model(or: feature.makeList))
        }

        public var body: some View {
            if host.slot != nil {
                shared
            } else {
                shared.navigationDestination(for: ScheduledRoute.self) { route in
                    ScheduledDestination(model: model, route: route, linkValue: linkValue)
                }
            }
        }

        /// The modifiers both platforms share, around the Mac's Table or the iOS List.
        private var shared: some View {
            content
                .overlay {
                    if model.isEmpty {
                        ContentUnavailableView {
                            Label(model.emptyTitle, systemImage: "clock")
                        } description: {
                            Text(model.emptyMessage)
                        } actions: {
                            // The same add flow as the toolbar button (D334.6).
                            Button(model.addTitle) { model.openNew() }
                        }
                    }
                }
                .navigationTitle(model.title)
                .toolbar {
                    // No shortcut: ⌘N stays New Transaction.
                    ToolbarItem(placement: .primaryAction) {
                        // "Add Scheduled Item" as its title, help and spoken name (D334.6). On the Mac it's the
                        // window's only + while Scheduled is selected.
                        Button(model.addTitle, systemImage: "plus") { model.openNew() }
                            .help(model.addTitle)
                    }
                }
                .navigationDestination(item: $openedItem) { id in
                    ScheduledItemView(model: model, itemID: id)
                }
                .scheduledSheets(model, on: .list)
                .onAppear {
                    // A form save is this window's Undo step (D351.1).
                    model.recordStep = { [undoHistory] change, name, subject in
                        undoHistory.record(change, named: name, subject: subject)
                    }
                    model.screenAppeared(.list)
                    model.load()
                    feature.watchNotices?.reload()
                }
                .onDisappear { model.screenDisappeared(.list) }
                .onChange(of: feature.revision) {
                    model.load()
                    // An item-changed card names the item as it's called now, or goes if it was deleted.
                    feature.watchNotices?.reload()
                }
        }

        /// The Mac shows a Table (D340.13); iOS keeps its List.
        @ViewBuilder private var content: some View {
            #if os(macOS)
                ScheduledTableView(model: model) { openedItem = $0 }
            #else
                list
            #endif
        }

        private var list: some View {
            List {
                if let notices = feature.watchNotices, let card = notices.card {
                    WatchRequestNoticeCardView(
                        card: card,
                        model: notices,
                        linkValue: linkValue,
                        openLink: host.openLink,
                    )
                }
                if let hint = model.catchUpHint {
                    Section {
                        Label(hint, systemImage: "info.circle")
                            // Shown only once it's really on screen, not when the list loads (D338.6).
                            .onAppear { model.catchUpHintAppeared() }
                    }
                }
                if !model.overdueRows.isEmpty {
                    Section {
                        if let hint = model.overdueHint {
                            Label(hint, systemImage: "exclamationmark.triangle")
                        }
                        ForEach(model.overdueRows) { row in
                            link(row)
                        }
                    } header: {
                        Text(model.overdueHeader)
                    }
                }
                if !model.dueTodayRows.isEmpty {
                    Section(model.dueTodayHeader) {
                        ForEach(model.dueTodayRows) { row in
                            link(row)
                        }
                    }
                }
                if !model.upcomingRows.isEmpty {
                    Section(model.upcomingHeader) {
                        ForEach(model.upcomingRows) { row in
                            link(row)
                        }
                    }
                }
                if let footer = model.automaticFooter {
                    Section {
                    } footer: {
                        Text(footer)
                    }
                }
                if !model.completedRows.isEmpty {
                    Section {
                        NavigationLink(value: linkValue(.completed)) {
                            LabeledContent(model.completedTitle, value: model.completedCount)
                        }
                    }
                }
            }
        }

        private func link(_ row: ScheduledRow) -> some View {
            NavigationLink(value: linkValue(.item(row.itemID))) {
                ScheduledRowView(row: row)
            }
            .contextMenu { ScheduledRowActions(model: model, row: row) }
        }
    }

    /// A screen pushed over the list, sharing the list's model. The Mac's list registers it; on iPhone and iPad the
    /// Accounts stack's root does.
    struct ScheduledDestination<Link: Hashable>: View {
        let model: ScheduledListViewModel
        let route: ScheduledRoute
        let linkValue: (ScheduledRoute) -> Link

        var body: some View {
            switch route {
            case .item(let id):
                ScheduledItemView(model: model, itemID: id)
            case .completed:
                ScheduledCompletedView(model: model, linkValue: linkValue)
            }
        }
    }

    /// A screen the iPhone and iPad Accounts stack's root builds over the list. It shares the list's model from the
    /// slot, even when it's built first, as when a reminder tap sets Scheduled and its item in one update (S33, Tech
    /// Architect 5661012630 B2). The list reloads that model after a change made elsewhere.
    struct ScheduledStackDestination<Link: Hashable>: View {
        @State private var model: ScheduledListViewModel
        private let route: ScheduledRoute
        private let linkValue: (ScheduledRoute) -> Link

        init(
            feature: ScheduledFeature,
            slot: ScheduledListSlot,
            onStack: Bool,
            route: ScheduledRoute,
            linkValue: @escaping (ScheduledRoute) -> Link,
        ) {
            self.route = route
            self.linkValue = linkValue
            _model = State(initialValue: slot.model(onStack: onStack, or: feature.makeList))
        }

        var body: some View {
            ScheduledDestination(model: model, route: route, linkValue: linkValue)
        }
    }

    /// The completed items, each a link to its screen.
    struct ScheduledCompletedView<Link: Hashable>: View {
        let model: ScheduledListViewModel
        let linkValue: (ScheduledRoute) -> Link

        var body: some View {
            List(model.completedRows) { row in
                NavigationLink(value: linkValue(.item(row.itemID))) {
                    ScheduledRowView(row: row)
                }
                .contextMenu { ScheduledRowActions(model: model, row: row) }
            }
            .overlay {
                if model.completedRows.isEmpty {
                    ContentUnavailableView(ScheduledText.noCompleted, systemImage: "checkmark.circle")
                }
            }
            .navigationTitle(model.completedTitle)
            .scheduledSheets(model, on: .completed)
            .onAppear { model.screenAppeared(.completed) }
            .onDisappear { model.screenDisappeared(.completed) }
        }
    }

    /// Pay Now and Skip This Occurrence for a due occurrence, then Edit and Delete for its item. On the Mac the
    /// items that ask first or open a sheet take an ellipsis, and Edit and Delete show ⌘E and ⌘⌫ (D334.10). Pay Now
    /// has no shortcut until it opens #201's sheet (D360.2, D361).
    struct ScheduledRowActions: View {
        let model: ScheduledListViewModel
        let row: ScheduledRow

        var body: some View {
            if row.canSettle {
                // No ⌘↩ until #201's "Pay ‹item›" sheet is on this base: it would record straight away (D360.2).
                // Whichever of #201 and #205 lands second wires ⌘↩ to open that sheet.
                Button(model.payNowTitle, systemImage: "checkmark.circle") { model.payNow(row) }
                Button(model.skipMenuTitle, systemImage: "forward") { model.confirmSkip(row) }
                Divider()
            }
            Button(model.editMenuTitle, systemImage: "pencil") { model.openEditor(row.itemID) }
                .macShortcut("e")
            Button(model.deleteMenuTitle, systemImage: "trash", role: .destructive) {
                model.confirmDelete(row.itemID)
            }
            .macShortcut(.delete)
        }
    }

    extension View {
        /// A ⌘ shortcut on the Mac menu item; iOS row menus show none.
        @ViewBuilder
        fileprivate func macShortcut(_ key: KeyEquivalent) -> some View {
            #if os(macOS)
                keyboardShortcut(key, modifiers: .command)
            #else
                self
            #endif
        }
    }

    /// One row: the type's symbol, the name and its repeat, then the amount and its date.
    struct ScheduledRowView: View {
        let row: ScheduledRow

        var body: some View {
            HStack {
                Label {
                    VStack(alignment: .leading) {
                        Text(verbatim: row.title)
                        Text(verbatim: row.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: row.symbolName)
                        .accessibilityHidden(true)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(verbatim: row.amount)
                        .foregroundStyle(row.tone.color)
                        .monospacedDigit()
                    if !row.dateText.isEmpty {
                        Text(verbatim: row.dateText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: row.spokenLabel))
            .accessibilityHint(Text(verbatim: row.detail))
        }
    }

    extension View {
        /// The form sheet, the Skip or Delete confirmation and the failure alert, attached by every Scheduled screen.
        /// Only the one on top (`ScheduledListViewModel.presenter`) presents, so a pushed screen shows them and the
        /// list under it never shows them a second time.
        func scheduledSheets(_ model: ScheduledListViewModel, on screen: ScheduledScreen) -> some View {
            modifier(ScheduledSheets(model: model, screen: screen))
        }
    }

    private struct ScheduledSheets: ViewModifier {
        @Bindable var model: ScheduledListViewModel
        let screen: ScheduledScreen

        private var presents: Bool { model.presenter == screen }

        private var form: Binding<ScheduledFormViewModel?> {
            Binding(get: { presents ? model.form : nil }, set: { model.form = $0 })
        }

        /// Skip and Delete on the Mac are alerts.
        private var showsAlertConfirmation: Binding<Bool> {
            Binding(
                get: { presents && model.confirmation.map { !Self.isDialog($0) } == true },
                set: { if !$0 { model.confirmation = nil } },
            )
        }

        /// Skip and Delete on iOS are confirmation dialogs (D334.8, D334.9).
        private var showsDialogConfirmation: Binding<Bool> {
            Binding(
                get: { presents && model.confirmation.map(Self.isDialog) == true },
                set: { if !$0 { model.confirmation = nil } },
            )
        }

        private var showsAlert: Binding<Bool> {
            Binding(get: { presents && model.alert != nil }, set: { if !$0 { model.alert = nil } })
        }

        private static func isDialog(_: ScheduledConfirmation) -> Bool {
            #if os(iOS)
                true
            #else
                false
            #endif
        }

        func body(content: Content) -> some View {
            content
                .sheet(item: form) { form in
                    NavigationStack {
                        ScheduledFormView(model: form)
                    }
                    .openSheet(hasUnsavedEdits: { form.hasUnsavedEdits }, close: { model.form = nil })
                }
                .alert(
                    model.confirmation?.title ?? "",
                    isPresented: showsAlertConfirmation,
                    presenting: model.confirmation,
                ) { confirmation in
                    Button(
                        confirmation.confirmTitle,
                        role: confirmation.isDestructive ? .destructive : nil,
                    ) { model.confirm() }
                    Button(model.cancelTitle, role: .cancel) { model.confirmation = nil }
                } message: { confirmation in
                    Text(confirmation.message)
                }
                .confirmationDialog(
                    model.confirmation?.title ?? "",
                    isPresented: showsDialogConfirmation,
                    titleVisibility: .visible,
                    presenting: model.confirmation,
                ) { confirmation in
                    // Skip records nothing and deletes nothing, so its button keeps the default role; Delete's is
                    // destructive.
                    Button(
                        confirmation.confirmTitle,
                        role: confirmation.isDestructive ? .destructive : nil,
                    ) { model.confirm() }
                    Button(model.cancelTitle, role: .cancel) { model.confirmation = nil }
                } message: { confirmation in
                    Text(confirmation.message)
                }
                .alert(
                    model.alert?.title ?? "",
                    isPresented: showsAlert,
                    presenting: model.alert,
                ) { _ in
                    Button(model.okayTitle) { model.alert = nil }
                } message: { alert in
                    Text(alert.message)
                }
        }
    }

    /// The card for a watch Pay or Skip the iPhone didn't apply (D374, D375, D376; UI Designer 6406964245,
    /// 6407229087): one list row with the title, a header for VoiceOver, the message, then View Item when it names
    /// one item, and OK, the default, which dismisses it for good. Standard List row pieces only. Both are buttons,
    /// so the row has no chevron and its text isn't a tap target; at accessibility text sizes they stack, so
    /// neither truncates.
    struct WatchRequestNoticeCardView<Link: Hashable>: View {
        let card: WatchRequestNoticeCard
        let model: WatchRequestNoticeViewModel
        /// The list's own route mapping: View Item opens the item the way the list's rows do (`AccountsRoute` on
        /// the iPhone and iPad Accounts stack, #198).
        let linkValue: (ScheduledRoute) -> Link
        /// Pushes onto the stack that owns the path; `nil` where the list registers its own destinations (the Mac).
        let openLink: ((Link) -> Void)?
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: card.title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: card.message)
                    buttonLayout {
                        if let route = model.viewItemRoute {
                            viewItem(linkValue(route))
                        }
                        if !dynamicTypeSize.isAccessibilitySize {
                            Spacer()
                        }
                        Button(model.okTitle) { model.dismiss() }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }

        private var buttonLayout: AnyLayout {
            dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout())
        }

        /// A button that pushes the list's own link value. Only where the list owns its stack (no `openLink`) is it
        /// a navigation link, styled as a button.
        @ViewBuilder
        private func viewItem(_ value: Link) -> some View {
            if let openLink {
                Button(model.viewItemTitle) { openLink(value) }
                    .buttonStyle(.bordered)
            } else {
                NavigationLink(value: value) {
                    Text(verbatim: model.viewItemTitle)
                }
                .buttonStyle(.bordered)
            }
        }
    }
#endif
