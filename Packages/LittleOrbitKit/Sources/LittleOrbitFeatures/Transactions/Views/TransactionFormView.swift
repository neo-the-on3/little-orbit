#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The transaction entry and edit sheet (#23). iOS: type switch, the amount typed on the decimal pad with
    /// a row of + − × ÷ = above it (D163), then Account, Category, Payee and Date, with More options for
    /// description and notes (Figma 26:751). macOS: a form sheet with a typed amount (Figma 28:1608, 28:1938).
    /// Return saves and Esc cancels.
    struct TransactionFormView: View {
        @State private var model: TransactionFormViewModel
        let updates: LedgerUpdates
        /// Edit Expense's Refund…, Duplicate and Delete; `nil` for a new transaction.
        let actions: TransactionFormActions?
        let onSaved: (TransactionChange) -> Void

        init(
            model: TransactionFormViewModel,
            updates: LedgerUpdates,
            actions: TransactionFormActions? = nil,
            onSaved: @escaping (TransactionChange) -> Void,
        ) {
            self.updates = updates
            _model = State(initialValue: model)
            self.actions = actions
            self.onSaved = onSaved
        }
        /// A button's action, run once the sheet has gone (`onDisappear`).
        @State private var afterClose: (() -> Void)?
        @Environment(\.dismiss) private var dismiss
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @State private var confirmingDiscard = false
        /// The calendar under the Date row at accessibility sizes.
        @State private var showsCalendar = false
        /// The text field being edited. The amount uses the decimal pad with the operator row; description
        /// and notes use the normal keyboard (D163).
        @FocusState private var focus: FormField?
        #if os(iOS)
            /// The category list and split editor pushed from the Category row (#34).
            @State private var path: [TransactionFormRoute] = []
        #endif

        enum FormField: Hashable {
            case amount, received, payee, description, notes
        }

        /// Scroll targets in the form.
        private enum Anchor: Hashable {
            case description
        }

        var body: some View {
            stack {
                content
                    .navigationTitle(model.title)
                    // Refunds recorded or deleted in another window update the form live (D225.1).
                    .onChange(of: updates.revision) { model.reload() }
                    #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel", action: cancel)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save", action: save)
                                .disabled(!model.canSave)
                        }
                    }
            }
            // With unsaved input the sheet can't be swiped away; Cancel asks first (UI Designer, #87 U3). SwiftUI
            // has no supported hook for a swipe attempt, so a swipe simply doesn't dismiss.
            .interactiveDismissDisabled(model.hasUnsavedInput)
            .confirmationDialog(
                "Discard this transaction?",
                isPresented: $confirmingDiscard,
                titleVisibility: .visible,
            ) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("The amount and details you entered will be lost.")
            }
            .alert(
                "Couldn’t save",
                isPresented: Binding(get: { model.errorMessage != nil }, set: { _ in }),
            ) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
            #if os(macOS)
                .frame(minWidth: 460, minHeight: 520)
            #endif
            .onDisappear { afterClose?() }
        }

        /// A Refund…, Duplicate or Delete button, once any discard is confirmed: closes the sheet, then acts.
        private func close(then action: @escaping () -> Void) {
            afterClose = action
            dismiss()
        }

        @ViewBuilder private var actionSections: some View {
            if let actions {
                TransactionFormActionSections(
                    actions: actions,
                    deleteTitle: model.deleteTitle,
                    deleteFootnote: model.deleteFootnote,
                    hasUnsavedInput: model.hasUnsavedInput,
                    close: { close(then: $0) },
                )
            }
        }

        /// The sheet's navigation stack; on iOS it can push the category list and the split editor.
        @ViewBuilder
        private func stack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
            #if os(iOS)
                NavigationStack(path: $path) {
                    content()
                        .navigationDestination(for: TransactionFormRoute.self) { route in
                            TransactionFormDestination(route: route, model: model, path: $path)
                        }
                }
            #else
                NavigationStack { content() }
            #endif
        }

        private func cancel() {
            if model.hasUnsavedInput {
                confirmingDiscard = true
            } else {
                dismiss()
            }
        }

        private func save() {
            // Nothing changed: close without a step (B4).
            if model.isUnchanged {
                dismiss()
                return
            }
            if let change = model.save() {
                onSaved(change)
                dismiss()
            }
        }

        // MARK: - Shared pieces

        @ViewBuilder private var accountRows: some View {
            if model.type == .transfer {
                StackedPickerRow("From", value: model.accountLabel(model.accountID)) {
                    Picker("From", selection: $model.accountID) { accountOptions }
                }
                StackedPickerRow("To", value: model.accountLabel(model.transferAccountID)) {
                    Picker("To", selection: $model.transferAccountID) {
                        Text("Choose").tag(UUID?.none)
                        accountOptions
                    }
                }
                if model.needsReceivedAmount {
                    labelledField("Received") {
                        TextField(
                            "Received",
                            text: $model.receivedText,
                            prompt: Text(model.receivedCurrencyCode ?? ""),
                        )
                        #if os(iOS)
                            .keyboardType(.decimalPad)
                        #endif
                        .focused($focus, equals: .received)
                    }
                    if let rate = model.rateText {
                        Label {
                            Text(rate)
                        } icon: {
                            Image(systemName: "arrow.left.arrow.right")
                                .accessibilityHidden(true)
                        }
                        .font(.theme(Self.footnoteStyle))
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                    }
                }
            } else {
                StackedPickerRow("Account", value: model.accountName) {
                    Picker("Account", selection: $model.accountID) { accountOptions }
                }
                if model.offersSplit {
                    TransactionCategoryRow(model: model)
                } else {
                    categoryPicker
                }
                payeeField
            }
            dateRow
        }

        @ViewBuilder private var categoryPicker: some View {
            StackedPickerRow("Category", value: model.categoryName, spoken: model.categorySpokenValue) {
                // The menu's items are standard Labels, so each lines up with its icon, in a section per
                // parent (UI Designer). The chosen value shows as text only, and its accessibility label
                // carries the parent, so VoiceOver reads "Category" then "Groceries, under Food & Dining"
                // once each: the iOS picker folds this label into its own, and the macOS one uses it as
                // the value (Tester's #87 v11).
                Picker(selection: $model.categoryID) {
                    Label("Uncategorised", systemImage: "questionmark").tag(UUID?.none)
                    CategoryPickerSections(groups: model.categoryGroups)
                } label: {
                    Text("Category")
                } currentValueLabel: {
                    Text(model.categoryName)
                        .accessibilityLabel(model.categorySpokenValue)
                }
            }
        }

        /// VoiceOver reads "Date, 21 October 2026" (UI Designer, #87 UI3). At accessibility sizes the label
        /// stacks above the date.
        /// At accessibility sizes the row is one button, "Date, 21 October 2026", that shows the calendar
        /// under it; the compact picker read "Date, Date" with a second picker button inside (Tester's #87
        /// recheck).
        @ViewBuilder private var dateRow: some View {
            // `pickerDate` does the zone work (D229.4, D230.1). This only pins the picker to the zone that value is
            // built in. In the app that's the environment's default anyway; it keeps the two in step if the
            // system zone changes while the sheet is open, or when a preview or test injects another zone.
            let picker = DatePicker("Date", selection: $model.pickerDate, displayedComponents: .date)
                .environment(\.timeZone, model.pickerTimeZone)
            if dynamicTypeSize.isAccessibilitySize {
                Button {
                    withAnimation { showsCalendar.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                        Text("Date")
                            .foregroundStyle(Color(ThemeColor.labelPrimary))
                        Text(model.dateSpokenText)
                            .foregroundStyle(Color(ThemeColor.accentDefault))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Date")
                .accessibilityValue(model.dateSpokenText)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(showsCalendar ? "Hides the calendar" : "Shows the calendar")
                if showsCalendar {
                    picker
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                }
            } else {
                picker
                    .accessibilityLabel("Date")
                    .accessibilityValue(model.dateSpokenText)
            }
        }

        /// A text field with a visible label. VoiceOver reads it as one element, labelled once, with the text
        /// (or prompt) as its value; `LabeledContent` with `.labelsHidden()` left the field unlabelled. On macOS
        /// the grouped form shows the field's own label. At accessibility sizes the label stacks above.
        @ViewBuilder
        private func labelledField<Content: View>(_ title: String, @ViewBuilder field: () -> Content) -> some View {
            #if os(macOS)
                field()
            #else
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                        Text(title)
                            .accessibilityHidden(true)
                        field()
                            .accessibilityLabel(title)
                    }
                    .accessibilityElement(children: .contain)
                } else {
                    HStack {
                        Text(title)
                            .accessibilityHidden(true)
                        Spacer()
                        field()
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel(title)
                    }
                    .accessibilityElement(children: .contain)
                }
            #endif
        }

        private var accountOptions: some View {
            ForEach(model.accountOptions) { option in
                Text(model.type == .transfer ? option.label : option.name).tag(Optional(option.id))
            }
        }

        @ViewBuilder private var payeeField: some View {
            labelledField("Payee") {
                TextField("Payee", text: $model.payeeText, prompt: Text("None"))
                    .autocorrectionDisabled()
                    .focused($focus, equals: .payee)
            }
            ForEach(model.payeeSuggestions) { suggestion in
                Button {
                    model.choosePayee(suggestion)
                } label: {
                    SuggestionLabel(suggestion: suggestion)
                }
                .buttonStyle(.plain)
            }
        }

        @ViewBuilder private var detailsFields: some View {
            VStack(alignment: .leading, spacing: Spacing.space1) {
                LimitedDescriptionField(text: model.details, axis: .vertical) { model.updateDetails($0) }
                    .focused($focus, equals: .description)
                if let footnote = model.detailsFootnote {
                    Text(footnote)
                        .font(.theme(Self.footnoteStyle))
                        .foregroundStyle(
                            Color(model.isDetailsOverLimit ? ThemeColor.statusOverspent : ThemeColor.labelSecondary)
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .id(Anchor.description)
            // Up to 3 suggestions, in a list under the field (UI Designer, #87 U1).
            ForEach(model.detailsSuggestions) { suggestion in
                Button {
                    model.chooseDescription(suggestion)
                } label: {
                    SuggestionLabel(suggestion: suggestion)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: Spacing.space1) {
                TextField("Notes", text: $model.note, prompt: Text("Notes"), axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityLabel("Notes")
                    .focused($focus, equals: .notes)
                Text(model.noteCounter)
                    .font(.theme(Self.footnoteStyle))
                    .foregroundStyle(Color(ThemeColor.labelSecondary))
            }
        }

        // MARK: - Platform layouts

        #if os(macOS)
            private var content: some View {
                Form {
                    if model.showsTypeSwitch {
                        typePicker
                    }
                    TextField("Amount:", text: $model.expressionInput, prompt: Text("0.00 or a sum like 50*20/10"))
                        .onSubmit { model.press(.equals) }
                    if let line = model.expressionLine {
                        Text("\(line) \(model.expressionText)")
                            .font(.theme(Self.footnoteStyle))
                            .foregroundStyle(Color(ThemeColor.labelSecondary))
                    }
                    messages
                    accountRows
                    detailsFields
                    ExpenseRefundsSection(rows: model.refundRows, footnote: model.refundsFootnote)
                    actionSections
                }
                .formStyle(.grouped)
            }

            private static let footnoteStyle = Typography.MacOS.footnote
        #else
            private var content: some View {
                VStack(spacing: Spacing.space2) {
                    if model.showsTypeSwitch {
                        typePicker
                            .padding(.horizontal, Layout.marginIOS)
                    }
                    TransactionAmountField(model: model, focus: $focus)
                        .padding(.horizontal, Layout.marginIOS)
                    ScrollViewReader { proxy in
                        Form {
                            Section { messages }
                            Section { accountRows }
                            Section {
                                moreOptionsButton
                                if model.showsMoreOptions {
                                    detailsFields
                                }
                            } footer: {
                                if !model.showsMoreOptions {
                                    Text("Description, notes")
                                }
                            }
                            ExpenseRefundsSection(rows: model.refundRows, footnote: model.refundsFootnote)
                            actionSections
                        }
                        .scrollDismissesKeyboard(.interactively)
                        // Keep the description and its suggestions above the keyboard (UI Designer, #87 U1).
                        .onChange(of: focus) { scrollToDescription(proxy) }
                        .onChange(of: model.detailsSuggestions.count) { scrollToDescription(proxy) }
                    }
                }
                .background(Color(ThemeColor.bgGrouped))
                // A new entry opens on the amount, so fast entry is "+, type 250, Save". The focus is set after
                // the sheet's first layout: set in `onAppear`, the keyboard came up before its toolbar was
                // built, and the operator row stayed missing until focus moved and came back (D170, D172 N1).
                .task {
                    guard model.mode.focusesAmountOnOpen else {
                        return
                    }
                    await Task.yield()
                    focus = .amount
                }
            }

            private func scrollToDescription(_ proxy: ScrollViewProxy) {
                guard focus == .description else {
                    return
                }
                withAnimation {
                    proxy.scrollTo(Anchor.description, anchor: .top)
                }
            }

            /// "More options" with its chevron as one button, labelled, with its expanded state (#87 B3).
            private var moreOptionsButton: some View {
                Button {
                    withAnimation { model.showsMoreOptions.toggle() }
                } label: {
                    HStack {
                        Text("More options")
                            .foregroundStyle(Color(ThemeColor.labelPrimary))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(model.showsMoreOptions ? 90 : 0))
                            .foregroundStyle(Color(ThemeColor.labelSecondary))
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("More options")
                .accessibilityValue(model.showsMoreOptions ? "Expanded" : "Collapsed")
                .accessibilityAddTraits(.isButton)
            }

            private static let footnoteStyle = Typography.IOS.footnote
        #endif
    }

    extension TransactionFormView {
        @ViewBuilder private var messages: some View {
            // On iOS the calculator error shows under the amount field instead (D163).
            #if os(macOS)
                if let error = model.amountError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(Color(ThemeColor.statusOverspent))
                }
            #endif
            if let issue = model.issueMessage {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color(ThemeColor.statusWarning))
            }
        }

        /// Hidden while the expense has refunds (`showsTypeSwitch`, D222.2).
        private var typePicker: some View {
            Picker("Type", selection: $model.type) {
                ForEach(model.allowedTypes, id: \.self) { type in
                    Text(TransactionFormViewModel.typeName(type)).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
#endif
