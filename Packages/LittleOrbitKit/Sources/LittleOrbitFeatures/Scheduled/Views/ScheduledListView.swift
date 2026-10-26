#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// The Scheduled list (#26 frames "Scheduled – overdue, due today, upcoming" on iOS and "Scheduled – overdue,
    /// due today, upcoming, completed; sidebar badge" on macOS). After a catch-up recorded something while the app
    /// was closed, an info hint comes first. Overdue starts with its hint row, then lists each missed occurrence on
    /// its own row; then Due Today, Upcoming and a Completed row with its count. Rows are standard navigation links
    /// to the item; the context menu has Pay Now, Skip This Occurrence, Edit and Delete. It sits inside the caller's
    /// NavigationStack. Whichever Scheduled screen is on top presents the form, confirmations and alerts. A watch Pay
    /// or Skip the iPhone didn't apply shows as a card above everything else until OK (D374, D376).
    ///
    /// The Mac gives the list its own stack, and the list registers the item and Completed destinations. On iPhone
    /// and iPad it's pushed onto the Accounts stack, whose typed path only takes `AccountsRoute` and only honours
    /// its root's destinations, so the links push `linkValue(route)` and the root builds the pushed screens with the
    /// model from `slot` (Tester's #198 iOS FAIL).
    public struct ScheduledListView<Link: Hashable>: View {
        @State private var model: ScheduledListViewModel
        private let feature: ScheduledFeature
        /// `nil` when the list registers its own destinations.
        private let slot: ScheduledListSlot?
        private let linkValue: (ScheduledRoute) -> Link

        /// A list that registers its own destinations (the Mac's detail column stack).
        public init(feature: ScheduledFeature) where Link == ScheduledRoute {
            self.init(feature: feature, slot: nil) { $0 }
        }

        /// A list on a stack whose root registers the destinations for `linkValue`'s values and builds them with the
        /// model in `slot` (the iPhone and iPad Accounts stack).
        init(feature: ScheduledFeature, slot: ScheduledListSlot?, linkValue: @escaping (ScheduledRoute) -> Link) {
            self.feature = feature
            self.slot = slot
            self.linkValue = linkValue
            _model = State(initialValue: feature.makeList())
        }

        public var body: some View {
            if let slot {
                list.onAppear { slot.attach(model) }
            } else {
                list.navigationDestination(for: ScheduledRoute.self) { route in
                    ScheduledDestination(model: model, route: route, linkValue: linkValue)
                }
            }
        }

        private var list: some View {
            List {
                if let notices = feature.watchNotices, let card = notices.card {
                    WatchRequestNoticeCardView(card: card, model: notices, linkValue: linkValue)
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
                ToolbarItem(placement: .primaryAction) {
                    Button(model.addTitle, systemImage: "plus") { model.openNew() }
                        .help(model.addTitle)
                }
            }
            .scheduledSheets(model, on: .list)
            .onAppear {
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
    /// slot. A path set in one go, such as a deep link straight to an item, can build it before the list under it has
    /// appeared, so then it makes its own model; either way the choice is made once, when the screen is first built.
    struct ScheduledStackDestination<Link: Hashable>: View {
        @State private var model: ScheduledListViewModel
        private let route: ScheduledRoute
        private let linkValue: (ScheduledRoute) -> Link

        init(
            feature: ScheduledFeature,
            slot: ScheduledListSlot,
            route: ScheduledRoute,
            linkValue: @escaping (ScheduledRoute) -> Link,
        ) {
            self.route = route
            self.linkValue = linkValue
            _model = State(initialValue: slot.model ?? feature.makeList())
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
    /// items that ask first or open a sheet take an ellipsis, and Pay Now, Edit and Delete show ⌘↩, ⌘E and ⌘⌫
    /// (D334.10).
    struct ScheduledRowActions: View {
        let model: ScheduledListViewModel
        let row: ScheduledRow

        var body: some View {
            if row.canSettle {
                Button(model.payNowTitle, systemImage: "checkmark.circle") { model.payNow(row) }
                    .macShortcut(.return)
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

    /// The card for a watch Pay or Skip the iPhone didn't apply (D374, D375, D376; UI Designer 6406964245): its
    /// title and message, then View Item when it names one item, and OK, the default, which dismisses it for good.
    /// Standard List row pieces only.
    struct WatchRequestNoticeCardView<Link: Hashable>: View {
        let card: WatchRequestNoticeCard
        let model: WatchRequestNoticeViewModel
        /// The list's own route mapping, so View Item opens the item on the iPhone and iPad Accounts stack too.
        let linkValue: (ScheduledRoute) -> Link

        var body: some View {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: card.title)
                        .font(.headline)
                    Text(verbatim: card.message)
                }
                HStack {
                    if let itemID = card.itemID {
                        NavigationLink(value: linkValue(.item(itemID))) {
                            Text(verbatim: model.viewItemTitle)
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button(model.okTitle) { model.dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
#endif
