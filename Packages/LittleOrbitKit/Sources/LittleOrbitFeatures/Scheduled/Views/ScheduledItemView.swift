#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// One scheduled item (#26: "tap an item for actions"): its amount and next due date, each overdue or due-today
    /// occurrence with its own Pay Now, Skip This Occurrence (S76) and Pay with Custom Date or Amount (D24), what it records, then Edit and Delete. While
    /// it's on top it presents the form, the confirmations and the alerts itself.
    struct ScheduledItemView: View {
        let model: ScheduledListViewModel
        let itemID: UUID
        var settling: ScheduledSettling = .dueOccurrences
        @Environment(WindowUndoHistory.self) private var undoHistory

        var body: some View {
            ScheduledItemContent(model: model, itemID: itemID, settling: settling)
                .scheduledSheets(model, on: .item(itemID))
                .onAppear {
                    // A form save is this window's Undo step (D351.1), also when a reminder tap opened the item
                    // straight onto the Mac stack and the list under it never appeared.
                    model.recordStep = { [undoHistory] change, name, subject in
                        undoHistory.record(change, named: name, subject: subject)
                    }
                    model.screenAppeared(.item(itemID))
                    model.loadIfNeeded()
                }
                .onDisappear { model.screenDisappeared(.item(itemID)) }
                // A reminder tap may give this screen another item without it disappearing (Tester2 6425404539).
                .onChange(of: itemID) { old, new in
                    model.screenChanged(from: .item(old), to: .item(new))
                }
        }
    }

    private struct ScheduledItemContent: View {
        let model: ScheduledListViewModel
        let itemID: UUID
        let settling: ScheduledSettling
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            if let detail = model.detail(itemID) {
                Form {
                    Section {
                        LabeledContent {
                            Text(verbatim: detail.amount)
                                .foregroundStyle(detail.tone.color)
                                .monospacedDigit()
                        } label: {
                            Text(verbatim: detail.next)
                        }
                    }
                    let settleable = model.settleableRows(of: itemID, settling)
                    if !settleable.isEmpty {
                        Section {
                            ForEach(settleable) { row in
                                // The status is the row's own text; each button is named by its title alone, not
                                // by the row's label (Tester's #198 Mac pass).
                                HStack {
                                    Text(verbatim: row.dateText)
                                    Spacer()
                                    Button(model.skipTitle) { model.confirmSkip(row) }
                                    Button(model.payNowTitle) { model.payNow(row) }
                                        .buttonStyle(.borderedProminent)
                                }
                                .buttonStyle(.bordered)
                                Button(model.payCustomTitle) { model.openCustomPay(row) }
                            }
                        }
                    }
                    Section {
                        ForEach(detail.facts) { fact in
                            LabeledContent(fact.label, value: fact.value)
                        }
                    }
                    Section {
                        Button(model.editTitle) { model.openEditor(itemID) }
                        Button(model.deleteTitle, role: .destructive) { model.confirmDelete(itemID) }
                    }
                }
                // Grouped, like the app's other forms: on the Mac each row spans the detail column, so the date
                // stays on the left and Skip and Pay Now sit inside its trailing edge (Tester's 8a99da5 Mac pass).
                .formStyle(.grouped)
                .navigationTitle(Text(verbatim: detail.title))
            } else if model.isGone(itemID) {
                // Deleted here or in another window.
                ContentUnavailableView(ScheduledText.emptyTitle, systemImage: "clock")
                    .onAppear { dismiss() }
            } else {
                // Not read yet: a new model, like the history row's sheet's, loads as the screen appears. Closing
                // here would close the sheet as soon as it opens (Tester's #203 iOS FAIL).
                ProgressView()
            }
        }
    }
#endif
