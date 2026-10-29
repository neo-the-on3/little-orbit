#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// Which scheduled item an account history's scheduled Upcoming row opens (S85), and the row's occurrence.
    struct ScheduledItemRoute: Identifiable, Hashable {
        let itemID: UUID
        let occurrence: CalendarDay?
        var id: UUID { itemID }
    }

    /// A scheduled item's own screen, opened from a scheduled Upcoming row in an account's history (S85). It offers
    /// Pay and Skip only when the row is the item's next occurrence, as the Scheduled list does; a later occurrence
    /// shows neither (D350.2). It's the Scheduled list's item screen in a sheet, with its own list model,
    /// so its confirmations, alerts and form show here; Done closes it. A deleted item closes it too.
    struct ScheduledItemSheet: View {
        let feature: ScheduledFeature
        let itemID: UUID
        let occurrence: CalendarDay?
        @State private var model: ScheduledListViewModel
        @Environment(\.dismiss) private var dismiss
        @Environment(WindowUndoHistory.self) private var undoHistory

        init(feature: ScheduledFeature, itemID: UUID, occurrence: CalendarDay?) {
            self.feature = feature
            self.itemID = itemID
            self.occurrence = occurrence
            _model = State(initialValue: feature.makeList())
        }

        var body: some View {
            NavigationStack {
                ScheduledItemView(model: model, itemID: itemID, settling: .historyRow(occurrence))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(CategoryText.done) { dismiss() }
                        }
                    }
            }
            .onAppear {
                // Its form's saves are steps in the window's own Undo history, as on the Scheduled list (D351.1).
                model.useUndoHistory(undoHistory)
                model.loadIfNeeded()
            }
            .onChange(of: feature.revision) { model.load() }
        }
    }
#endif
