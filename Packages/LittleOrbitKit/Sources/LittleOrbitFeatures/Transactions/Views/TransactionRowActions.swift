#if canImport(SwiftUI) && (os(macOS) || os(iOS))
    import LittleOrbitDomain
    import SwiftUI

    /// Duplicate in a row's menu (D65). A refund doesn't show it (UI Designer, 23 Oct). iOS menus show the
    /// Duplicate icon (S58); macOS menus have no icons.
    struct DuplicateMenuButton: View {
        let action: () -> Void

        var body: some View {
            #if os(iOS)
                Button(action: action) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
            #else
                Button("Duplicate", action: action)
            #endif
        }
    }

    #if os(iOS)
        /// The iOS long-press menu (UI Designer, 23 Oct): Edit, Duplicate, Refund…, a divider, then Delete,
        /// destructive and last. A refund shows neither Duplicate nor Refund…; income and transfers show no
        /// Refund… (D117.2).
        struct TransactionRowMenu: View {
            let offersDuplicate: Bool
            let offersRefund: Bool
            let onEdit: () -> Void
            let onDuplicate: () -> Void
            let onRefund: () -> Void
            let onDelete: () -> Void

            var body: some View {
                Button(action: onEdit) {
                    Label("Edit Transaction", systemImage: "pencil")
                }
                if offersDuplicate {
                    DuplicateMenuButton(action: onDuplicate)
                }
                if offersRefund {
                    Button(action: onRefund) {
                        Label("Refund…", systemImage: "arrow.uturn.backward")
                    }
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Transaction", systemImage: "trash")
                }
            }
        }

        /// The iOS row swipe (D117.2, S58): Refund · Duplicate · Delete on an expense, Duplicate · Delete on income
        /// and transfers, and only Delete on a refund. Delete is last and a full swipe deletes. These are the
        /// system swipe actions, and the row's only ones, so VoiceOver lists each action once.
        struct TransactionSwipeActions: ViewModifier {
            let offersRefund: Bool
            let offersDuplicate: Bool
            let onRefund: () -> Void
            let onDuplicate: () -> Void
            let onDelete: () -> Void

            func body(content: Content) -> some View {
                content.swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    // The first is the trailing one, which a full swipe runs.
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                    if offersDuplicate {
                        Button(action: onDuplicate) {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                    }
                    if offersRefund {
                        Button(action: onRefund) {
                            Label {
                                // The verb has its own catalog entry; "Refund" alone is the noun (D233.5).
                                Text(
                                    String(
                                        localized: "Refund (swipe action)",
                                        defaultValue: "Refund",
                                        bundle: .module,
                                        comment:
                                            "iOS swipe action that records a refund of the expense: the verb. The row title “Refund” is the noun and has its own entry.",
                                    )
                                )
                            } icon: {
                                Image(systemName: "arrow.uturn.backward")
                            }
                        }
                    }
                }
            }
        }
    #endif
#endif
