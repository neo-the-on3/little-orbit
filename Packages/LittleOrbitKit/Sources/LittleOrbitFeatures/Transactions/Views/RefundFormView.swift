#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// The refund sheet (#34, D65), from the final #34 designs, in a standard Form with the system toolbar and
    /// controls. iOS: "Refund of" and "Refundable" with the footnote, then Amount, Account, Category, Payee and
    /// Date. macOS (⌘R): the caption, then Amount with what's refundable, Account, Category from the expense,
    /// Payee and Date. The payee is editable text prefilled from the expense (D234.4, D235). The sheet follows
    /// live data while it's open, keeping what was typed. Return saves and Esc cancels.
    struct RefundFormView: View {
        @State private var model: RefundFormViewModel
        let updates: LedgerUpdates
        let onSaved: (TransactionChange) -> Void
        @Environment(\.dismiss) private var dismiss

        init(model: RefundFormViewModel, updates: LedgerUpdates, onSaved: @escaping (TransactionChange) -> Void) {
            _model = State(initialValue: model)
            self.updates = updates
            self.onSaved = onSaved
        }

        var body: some View {
            NavigationStack {
                form
                    .navigationTitle("Refund")
                    #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save", action: save)
                                .disabled(!model.canSave)
                        }
                    }
            }
            // Any change to the shared store, from this window or another, rechecks the refund (D227.3).
            .onChange(of: updates.revision) { model.reload() }
            .alert(
                "Couldn’t save",
                isPresented: Binding(get: { model.errorMessage != nil }, set: { _ in }),
            ) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
            #if os(macOS)
                .frame(minWidth: 460)
            #endif
        }

        private func save() {
            if let change = model.save() {
                onSaved(change)
                dismiss()
            }
        }

        private var accountPicker: some View {
            Picker(Self.accountLabel, selection: $model.accountID) {
                ForEach(model.accountOptions) { option in
                    Text(option.label).tag(Optional(option.id))
                }
            }
        }

        private var datePicker: some View {
            // `pickerDate` does the zone work (D229.4, D230.1); this pins the picker to the zone it's built in.
            DatePicker(Self.dateLabel, selection: $model.pickerDate, displayedComponents: .date)
                .environment(\.timeZone, model.pickerTimeZone)
        }

        /// The payee as plain editable text, prefilled from the expense; emptied, the refund saves with none
        /// (D234.4, D235). SwiftUI has no system clear button for a text field, so there isn't one.
        @ViewBuilder private var payeeRow: some View {
            #if os(macOS)
                TextField(Self.payeeLabel, text: $model.payeeText)
            #else
                LabeledContent(Self.payeeLabel) {
                    TextField(Self.payeeLabel, text: $model.payeeText)
                        .multilineTextAlignment(.trailing)
                }
            #endif
        }

        /// What stops the refund from saving, in the form's order (D35, D33, D97.4).
        @ViewBuilder private var messages: some View {
            ForEach(model.messages, id: \.self) { message in
                Text(message)
                    .foregroundStyle(Color(ThemeColor.statusOverspent))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        #if os(macOS)
            private static let accountLabel = "Account:"
            private static let dateLabel = "Date:"
            private static let payeeLabel = "Payee:"

            private var form: some View {
                Form {
                    Text(model.caption)
                        .font(.theme(Typography.MacOS.footnote))
                        .foregroundStyle(Color(ThemeColor.labelSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                    LabeledContent("Amount:") {
                        HStack {
                            TextField("Amount", text: $model.amountText)
                                .labelsHidden()
                            Text(model.amountSuffix)
                                .foregroundStyle(Color(ThemeColor.labelSecondary))
                        }
                    }
                    accountPicker
                    LabeledContent("Category:", value: model.categoryFromExpenseText)
                    payeeRow
                    datePicker
                    messages
                }
                .padding()
            }
        #else
            private static let accountLabel = "Account"
            private static let dateLabel = "Date"
            private static let payeeLabel = "Payee"

            private var form: some View {
                Form {
                    Section {
                        LabeledContent("Refund of", value: model.refundOfText)
                        LabeledContent("Refundable", value: model.refundableText)
                    } footer: {
                        Text(model.footnote)
                    }
                    Section {
                        LabeledContent("Amount") {
                            TextField("Amount", text: $model.amountText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        accountPicker
                        LabeledContent("Category", value: model.categoryName)
                        payeeRow
                        datePicker
                    } footer: {
                        VStack(alignment: .leading) {
                            messages
                        }
                    }
                }
            }
        #endif
    }
#endif
