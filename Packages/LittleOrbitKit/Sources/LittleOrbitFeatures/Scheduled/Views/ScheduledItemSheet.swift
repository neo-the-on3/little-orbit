#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import SwiftUI

    /// Which scheduled item an account history's scheduled Upcoming row opens (S85).
    struct ScheduledItemRoute: Identifiable, Hashable {
        let itemID: UUID
        var id: UUID { itemID }
    }

    /// A scheduled item's own screen, with Pay and Skip for its due occurrences, opened from a scheduled Upcoming
    /// row in an account's history (S85). It's the Scheduled list's item screen in a sheet, with its own list model,
    /// so its confirmations, alerts and form show here; Done closes it. A deleted item closes it too.
    struct ScheduledItemSheet: View {
        let feature: ScheduledFeature
        let itemID: UUID
        @State private var model: ScheduledListViewModel
        @Environment(\.dismiss) private var dismiss

        init(feature: ScheduledFeature, itemID: UUID) {
            self.feature = feature
            self.itemID = itemID
            _model = State(initialValue: feature.makeList())
        }

        var body: some View {
            NavigationStack {
                ScheduledItemView(model: model, itemID: itemID)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(CategoryText.done) { dismiss() }
                        }
                    }
            }
            .onAppear { model.load() }
            .onChange(of: feature.revision) { model.load() }
        }
    }
#endif
