#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    /// Pay with Custom Date or Amount (D24, #197 design answers): a standard sheet titled "Pay ‹item›", Cancel and
    /// Record, with a Form of the amount and its "Scheduled amount" footer, the "Paid on" date picker, up to today, the
    /// account (From for a transfer), the category, and "Also change future occurrences" (a checkbox on the Mac) with its footer. Standard Form controls only.
    struct ScheduledPayView: View {
        @Bindable var model: ScheduledPayViewModel
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            Form {
                Section {
                    TextField(model.amountLabel, text: $model.amountText)
                        #if os(iOS)
                            .keyboardType(.decimalPad)
                        #endif
                    if let error = model.amountError {
                        Text(error).foregroundStyle(Color(ThemeColor.destructiveDefault))
                    }
                } footer: {
                    Text(model.amountFooter)
                }
                Section {
                    DatePicker(
                        model.paidOnLabel,
                        selection: $model.date,
                        in: ...model.latestDate,
                        displayedComponents: .date,
                    )
                    Picker(model.accountLabel, selection: $model.accountID) {
                        ForEach(model.accountChoices) { Text(verbatim: $0.name).tag($0.id) }
                    }
                    if model.showsCategory {
                        Picker(model.categoryLabel, selection: $model.categoryID) {
                            ForEach(model.categoryChoices) { Text(verbatim: $0.name).tag($0.id) }
                        }
                    }
                }
                Section {
                    // A switch on iOS, a checkbox on the Mac (D340).
                    Toggle(model.changeFutureLabel, isOn: $model.changesFutureOccurrences)
                        #if os(macOS)
                            .toggleStyle(.checkbox)
                        #endif
                        // A grouped Form on the Mac draws the checkbox's title as separate text, so the checkbox was
                        // unnamed without this (Tester's Mac accessibility pass at 59017dc).
                        .accessibilityLabel(Text(model.changeFutureLabel))
                } footer: {
                    Text(model.changeFutureFooter)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text(verbatim: model.title))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Tester's Mac accessibility pass at 59017dc: the title was only the description.
                    Button(model.cancelTitle) { dismiss() }
                        .accessibilityLabel(Text(model.cancelTitle))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.confirmTitle) {
                        if model.record() {
                            dismiss()
                        }
                    }
                    .accessibilityLabel(Text(model.confirmTitle))
                }
            }
            .alert(
                model.alert?.title ?? "",
                isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
                presenting: model.alert,
            ) { _ in
                // Tester's Mac accessibility pass at 59017dc: the title was only the description.
                Button(model.okayTitle) { model.alert = nil }
                    .accessibilityLabel(Text(model.okayTitle))
            } message: { alert in
                Text(alert.message)
            }
        }
    }
#endif
