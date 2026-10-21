#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The add, edit and first-account form (Figma 14:1424 iOS sheets, 14:1846 macOS sheet).
    public struct AccountFormView: View {
        @State private var model: AccountFormViewModel
        @Environment(\.dismiss) private var dismiss
        private let onSaved: (Account) -> Void
        private let onDelete: ((UUID) -> Void)?

        public init(
            model: AccountFormViewModel,
            onSaved: @escaping (Account) -> Void,
            onDelete: ((UUID) -> Void)? = nil,
        ) {
            _model = State(initialValue: model)
            self.onSaved = onSaved
            self.onDelete = onDelete
        }

        public var body: some View {
            #if os(macOS)
                macBody
            #else
                iOSBody
            #endif
        }

        private func save() {
            if let account = model.save() {
                onSaved(account)
                dismiss()
            }
        }

        // MARK: - Sections

        @ViewBuilder private var nameField: some View {
            TextField("Account name", text: $model.name)
                .accessibilityLabel("Account name")
        }

        @ViewBuilder private var typePicker: some View {
            Picker("Type", selection: $model.type) {
                ForEach(AccountType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
        }

        @ViewBuilder private var iconPicker: some View {
            Picker("Icon", selection: $model.iconSymbol) {
                ForEach(model.iconOptions, id: \.symbolName) { icon in
                    Label(icon.displayName, systemImage: icon.symbolName).tag(icon.symbolName)
                }
            }
        }

        @ViewBuilder private var currencyPicker: some View {
            Picker("Currency", selection: $model.currencyCode) {
                ForEach(model.currencyOptions, id: \.self) { code in
                    Text(model.currencyTitle(for: code)).tag(code)
                }
            }
            .disabled(model.isCurrencyLocked)
        }

        @ViewBuilder private var amountField: some View {
            TextField("Opening balance", text: $model.amountText, prompt: Text("0.00"))
                #if os(iOS)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                #endif
                .font(.theme(amountStyle))
        }

        @ViewBuilder private var messages: some View {
            if let error = model.nameError {
                Text(error).foregroundStyle(Color(ThemeColor.destructiveDefault))
            } else if let hint = model.duplicateHint {
                Text(hint).foregroundStyle(Color(ThemeColor.labelSecondary))
            }
            if let error = model.amountError {
                Text(error).foregroundStyle(Color(ThemeColor.destructiveDefault))
            }
            if model.isCurrencyLocked {
                Text(model.currencyLockMessage).foregroundStyle(Color(ThemeColor.labelSecondary))
            }
            if let error = model.loadError {
                Text(error).foregroundStyle(Color(ThemeColor.destructiveDefault))
            }
            if let error = model.saveError {
                Text(error).foregroundStyle(Color(ThemeColor.destructiveDefault))
            }
        }

        @ViewBuilder private var creditSection: some View {
            if model.showsCreditLimit {
                Section {
                    #if os(iOS)
                        labelledField("Credit limit") {
                            TextField("Credit limit", text: $model.creditLimitText, prompt: Text("Optional"))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    #else
                        TextField("Credit limit:", text: $model.creditLimitText, prompt: Text("Optional"))
                            .accessibilityLabel("Credit limit")
                    #endif
                    if model.showsAvailableCreditToggle {
                        Toggle("Show available credit", isOn: $model.showAvailableCredit)
                    }
                } header: {
                    Text("Credit")
                } footer: {
                    if let error = model.creditLimitError {
                        Text(error).foregroundStyle(Color(ThemeColor.destructiveDefault))
                    }
                }
            }
        }

        @ViewBuilder private var visibilitySection: some View {
            Section {
                Toggle("Hide account", isOn: $model.isHidden)
                Toggle("Exclude from net wealth", isOn: $model.excludeFromNetWealth)
            } header: {
                Text("Visibility")
            } footer: {
                Text(model.visibilityFooter)
            }
        }

        // MARK: - iOS

        #if os(iOS)
            private var amountStyle: TypeStyle { Typography.Amount.iOSBody }

            private var iOSBody: some View {
                NavigationStack {
                    Form {
                        if model.mode == .firstAccount {
                            firstAccountSections
                        } else {
                            fullSections
                        }
                    }
                    .navigationTitle(model.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(model.confirmTitle, action: save)
                                .disabled(!model.canSave)
                        }
                    }
                }
            }

            /// A visible label with its field on the right (Figma 5:1539), read by VoiceOver as one element:
            /// the field, labelled with the title exactly once, with its value (or prompt) as the value. The
            /// visible text is hidden from VoiceOver and the field keeps an explicit label, because
            /// `.labelsHidden()` would leave the field unlabelled and `LabeledContent` reads the title twice
            /// (#82 B1).
            private func labelledField(_ title: String, @ViewBuilder field: () -> some View) -> some View {
                HStack {
                    Text(title)
                        .accessibilityHidden(true)
                    Spacer()
                    field()
                        .accessibilityLabel(title)
                }
                .accessibilityElement(children: .contain)
            }

            @ViewBuilder private var firstAccountSections: some View {
                Section {
                    nameField
                    labelledField("Balance today") { amountField }
                    currencyPicker
                } footer: {
                    VStack(alignment: .leading, spacing: Spacing.space1) {
                        Text("You can add more accounts and change the type later.")
                        messages
                    }
                }
            }

            @ViewBuilder private var fullSections: some View {
                Section {
                    nameField
                    typePicker
                    iconPicker
                    currencyPicker
                    labelledField("Opening balance") { amountField }
                } footer: {
                    VStack(alignment: .leading, spacing: Spacing.space1) { messages }
                }
                Section {
                    Toggle(model.signToggleTitle, isOn: $model.flipsSign)
                } footer: {
                    Text(model.signFooter)
                }
                creditSection
                visibilitySection
                if model.isEditing, case .edit(let id) = model.mode, let onDelete {
                    Section {
                        // The presenter confirms over this sheet and closes it after Hide or Delete (bug 3).
                        Button("Delete Account…", role: .destructive) { onDelete(id) }
                    }
                }
            }
        #endif

        // MARK: - macOS

        #if os(macOS)
            private var amountStyle: TypeStyle { Typography.Amount.macOSBody }

            private var macBody: some View {
                VStack(alignment: .leading, spacing: Spacing.space4) {
                    Text(model.title)
                        .font(.theme(Typography.MacOS.headline))
                    Form {
                        nameField
                        if model.mode != .firstAccount {
                            typePicker
                            iconPicker
                        }
                        currencyPicker
                        amountField
                        if model.mode != .firstAccount {
                            Toggle(model.signToggleTitle, isOn: $model.flipsSign)
                            Text(model.signFooter)
                                .font(.theme(Typography.MacOS.footnote))
                                .foregroundStyle(Color(ThemeColor.labelSecondary))
                        }
                        messages
                            .font(.theme(Typography.MacOS.footnote))
                        if model.mode != .firstAccount {
                            creditSection
                            visibilitySection
                        }
                    }
                    .formStyle(.grouped)
                    HStack {
                        if model.isEditing, case .edit(let id) = model.mode, let onDelete {
                            Button("Delete Account…", role: .destructive) { onDelete(id) }
                        }
                        Spacer()
                        Button("Cancel") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                        Button(model.confirmTitle, action: save)
                            .keyboardShortcut(.defaultAction)
                            .disabled(!model.canSave)
                    }
                }
                .padding(Layout.marginMacOS)
                .frame(minWidth: 440, idealWidth: 480, minHeight: 360)
            }
        #endif
    }
#endif
