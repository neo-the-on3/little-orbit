#if canImport(SwiftUI) && os(watchOS)
    import LittleOrbitDomain
    import SwiftUI

    /// The watch's Scheduled list (#32 Watch Scheduled list frame): each overdue occurrence on its own row (D340.6),
    /// then due today, then each item's next date. A row opens Pay and Skip (the Watch Pay frame); a syncing row
    /// shows a clock (the Watch syncing frame). A Pay or Skip the iPhone turned down shows as a system alert with OK
    /// (the Watch conflict frame, D342, D343). Before the first snapshot it says it isn't synced yet (UI Designer
    /// 6406964245, 6407229087). System controls throughout.
    public struct WatchScheduledListView: View {
        let model: WatchScheduledViewModel

        public init(model: WatchScheduledViewModel) {
            self.model = model
        }

        public var body: some View {
            NavigationStack {
                Group {
                    if model.isWaitingForIPhone {
                        ContentUnavailableView {
                            Label(model.notSyncedTitle, systemImage: "iphone")
                        } description: {
                            Text(model.notSyncedMessage)
                        }
                    } else if model.isEmpty {
                        ContentUnavailableView(model.emptyTitle, systemImage: "clock")
                    } else {
                        List(model.rows) { row in
                            NavigationLink(value: row.id) {
                                WatchScheduledRowView(row: row)
                            }
                            .disabled(row.isPending)
                        }
                    }
                }
                .navigationTitle(model.title)
                .navigationDestination(for: UUID.self) { id in
                    WatchScheduledPayView(model: model, id: id)
                }
            }
            .alert(
                Text(verbatim: model.conflict?.title ?? ""),
                isPresented: Binding(
                    get: { model.conflict != nil },
                    set: { isPresented in
                        if !isPresented {
                            model.closeConflict()
                        }
                    },
                ),
                presenting: model.conflict,
                actions: { _ in },
                message: { conflict in Text(verbatim: conflict.message) },
            )
        }
    }

    struct WatchScheduledRowView: View {
        let row: WatchScheduledRow

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: row.title)
                        .font(.headline)
                    Spacer(minLength: 4)
                    // Amounts are never truncated (S68).
                    Text(verbatim: row.amount)
                        .font(.headline)
                        .monospacedDigit()
                        .fixedSize()
                }
                Label {
                    Text(verbatim: row.dateText)
                } icon: {
                    Image(systemName: row.symbolName)
                }
                .font(.footnote)
                .foregroundStyle(row.isPending ? Color.secondary : (row.isOverdue ? Color.red : Color.secondary))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: row.spokenLabel))
        }
    }

    /// Pay or Skip one occurrence (#32 Watch Pay frame): its name, amount and due line, then Pay and Skip. Both
    /// go back to the list, where the row shows it's syncing until the iPhone confirms.
    struct WatchScheduledPayView: View {
        let model: WatchScheduledViewModel
        let id: UUID
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            if let row = model.row(id) {
                ScrollView {
                    VStack(spacing: 6) {
                        Text(verbatim: row.title)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Text(verbatim: row.amount)
                            .font(.title2)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(verbatim: row.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button(model.payTitle) {
                            model.pay(id)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        Button(model.skipTitle) {
                            model.skip(id)
                            dismiss()
                        }
                    }
                    .disabled(row.isPending)
                }
                .navigationTitle(model.title)
            } else {
                ContentUnavailableView(model.emptyTitle, systemImage: "clock")
            }
        }
    }
#endif
