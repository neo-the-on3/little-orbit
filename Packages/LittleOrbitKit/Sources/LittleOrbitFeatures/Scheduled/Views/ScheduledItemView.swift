#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// One scheduled item (#26: "tap an item for actions"): its amount and next due date, each overdue or due-today
    /// occurrence with its own Pay Now and Skip This Occurrence (S76), what it records, then Edit and Delete. While
    /// it's on top it presents the form, the confirmations and the alerts itself.
    struct ScheduledItemView: View {
        let model: ScheduledListViewModel
        let itemID: UUID

        var body: some View {
            ScheduledItemContent(model: model, itemID: itemID)
                .scheduledSheets(model, on: .item(itemID))
                .onAppear { model.screenAppeared(.item(itemID)) }
                .onDisappear { model.screenDisappeared(.item(itemID)) }
        }
    }

    private struct ScheduledItemContent: View {
        let model: ScheduledListViewModel
        let itemID: UUID
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
                    if !detail.due.isEmpty {
                        Section {
                            ForEach(detail.due) { row in
                                // The status is the row's own text; each button is named by its title alone, not
                                // by the row's label (Tester's #198 Mac pass).
                                HStack {
                                    Text(verbatim: row.dateText)
                                    Spacer()
                                    Button(model.skipTitle) { model.confirmSkip(row) }
                                        .accessibilityLabel(Text(model.skipTitle))
                                    Button(model.payNowTitle) { model.payNow(row) }
                                        .accessibilityLabel(Text(model.payNowTitle))
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
                .navigationTitle(Text(verbatim: detail.title))
            } else {
                // Deleted here or in another window.
                ContentUnavailableView(ScheduledText.emptyTitle, systemImage: "clock")
                    .onAppear { dismiss() }
            }
        }
    }
#endif
