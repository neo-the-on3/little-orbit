#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import LittleOrbitTheme
    import SwiftUI

    #if os(iOS)
        import UIKit
    #endif

    /// New and Edit Scheduled Item (#26 frame "New scheduled – form, 31st rule preview"): type, amount, payee (the #23
    /// autocomplete with Create, #197), category and account; then Schedule (Starts, Repeat with its stepper row,
    /// Ends and End Date), the Next Due Dates preview with its month-end footnote (D24), and Process automatically.
    /// Standard Form controls only.
    struct ScheduledFormView: View {
        @Bindable var model: ScheduledFormViewModel
        @Environment(\.dismiss) private var dismiss
        @Environment(\.openURL) private var openURL
        @Environment(\.scenePhase) private var scenePhase

        var body: some View {
            Form {
                Section {
                    // The segmented control hides its label; VoiceOver reads it as "Type".
                    Picker(model.typeLabel, selection: $model.type) {
                        ForEach(TransactionType.allCases, id: \.self) { type in
                            Text(model.typeName(type)).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Section {
                    TextField(model.amountLabel, text: $model.amountText)
                        #if os(iOS)
                            .keyboardType(.decimalPad)
                        #endif
                    if let error = model.amountError {
                        Text(error).foregroundStyle(Color(ThemeColor.destructiveDefault))
                    }
                    TextField(model.descriptionLabel, text: $model.details)
                }
                Section {
                    if model.showsCategory {
                        // The #23 payee autocomplete: matching payees, then Create for a new name (#197).
                        TextField(model.payeeLabel, text: $model.payeeText, prompt: Text(model.payeePrompt))
                        ForEach(model.payeeSuggestions) { suggestion in
                            Button {
                                model.choosePayee(suggestion)
                            } label: {
                                Label(suggestion.text, systemImage: "person")
                            }
                        }
                        if let create = model.createPayeeTitle {
                            Button {
                                model.createPayee()
                            } label: {
                                Label {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: create)
                                        Text(model.createPayeeSubtitle)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "plus.circle")
                                }
                            }
                        }
                        Picker(model.categoryLabel, selection: $model.categoryID) {
                            ForEach(model.categoryChoices) { Text(verbatim: $0.name).tag($0.id) }
                        }
                    }
                    Picker(model.accountLabel, selection: $model.accountID) {
                        ForEach(model.accountChoices) { Text(verbatim: $0.name).tag($0.id) }
                    }
                    if model.type == .transfer {
                        Picker(model.toLabel, selection: $model.transferAccountID) {
                            ForEach(model.toChoices) { Text(verbatim: $0.name).tag($0.id) }
                        }
                    }
                    if let error = model.formError {
                        Text(error).foregroundStyle(Color(ThemeColor.destructiveDefault))
                    }
                }
                Section(model.scheduleHeader) {
                    DatePicker(model.startsLabel, selection: $model.startDate, displayedComponents: .date)
                    Picker(model.repeatLabel, selection: $model.frequency) {
                        ForEach(ScheduledFrequency.allCases) { Text(model.frequencyName($0)).tag($0) }
                    }
                    if model.frequency != .never {
                        // The whole phrase: "Monthly" at 1, "Every 2 months" at 2 (D334.4).
                        Stepper(value: $model.interval, in: model.intervalRange) {
                            Text(model.intervalText)
                        }
                        Picker(model.endsLabel, selection: $model.hasEnd) {
                            Text(model.endsNeverTitle).tag(false)
                            Text(model.endsOnDateTitle).tag(true)
                        }
                        if model.hasEnd {
                            DatePicker(model.endDateLabel, selection: $model.endDate, displayedComponents: .date)
                        }
                    }
                }
                Section {
                    ForEach(model.preview) { row in
                        LabeledContent(row.date, value: row.note ?? "")
                    }
                } header: {
                    Text(model.previewHeader)
                } footer: {
                    if let footnote = model.previewFootnote {
                        Text(footnote)
                    }
                }
                Section {
                    // Each switch is named by its visible title: in the Mac Form the title is separate text, so
                    // the switch had no description (Tester2's #204 Mac pass at 38050b0).
                    Toggle(model.automaticLabel, isOn: $model.processesAutomatically)
                        .accessibilityLabel(Text(model.automaticLabel))
                    Toggle(model.notifyLabel, isOn: $model.notifiesWhenDue)
                        .accessibilityLabel(Text(model.notifyLabel))
                    TextField(model.noteLabel, text: $model.note, axis: .vertical)
                } footer: {
                    Text(model.footnote)
                }
                // Open Settings and the sentence saying why sit together in their own section (D341.3).
                if model.showsOpenSettings, let url = ScheduledFormView.notificationSettingsURL {
                    Section {
                        Button(model.openSettingsTitle) { openURL(url) }
                    } footer: {
                        Text(model.notificationsOffFootnote)
                    }
                }
            }
            .formStyle(.grouped)
            .onChange(of: scenePhase) { _, phase in
                // Back from Settings, where notifications may have been turned on.
                if phase == .active {
                    model.refreshNotificationPermission()
                }
            }
            .navigationTitle(model.title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.cancelTitle) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.confirmTitle) {
                        if model.save() {
                            dismiss()
                        }
                    }
                }
            }
            .alert(
                model.alert?.title ?? "",
                isPresented: $model.isAlertPresented,
                presenting: model.alert,
            ) { _ in
                // The cancel role makes Esc on the Mac this OK. Either way the alert's dismissal closes the form when
                // its item was deleted elsewhere (#258).
                Button(model.okayTitle, role: .cancel) {}
            } message: { alert in
                Text(alert.message)
            }
            .onChange(of: model.closeRequested) { _, closes in
                if closes {
                    dismiss()
                }
            }
        }

        /// The app's notification settings: its page in iOS Settings, or Notifications in System Settings.
        @MainActor static var notificationSettingsURL: URL? {
            #if os(iOS)
                URL(string: UIApplication.openNotificationSettingsURLString)
            #else
                URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
            #endif
        }
    }
#endif
