#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// One scheduled item (#26: "tap an item for actions"): its amount and next due date, each overdue or due-today
    /// occurrence with its own Pay Now and Skip This Occurrence (S76), what it records, then Edit and Delete. While
    /// it's on top it presents the form, the confirmations and the alerts itself.
    struct ScheduledItemView: View {
        let model: ScheduledListViewModel
        let itemID: UUID
        var settling: ScheduledSettling = .dueOccurrences

        var body: some View {
            ScheduledItemContent(model: model, itemID: itemID, settling: settling)
                .scheduledSheets(model, on: .item(itemID))
                .onAppear { model.screenAppeared(.item(itemID)) }
                .onDisappear { model.screenDisappeared(.item(itemID)) }
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
            } else {
                // Deleted here or in another window.
                ContentUnavailableView(ScheduledText.emptyTitle, systemImage: "clock")
                    .onAppear { dismiss() }
            }
        }
    }
#endif
