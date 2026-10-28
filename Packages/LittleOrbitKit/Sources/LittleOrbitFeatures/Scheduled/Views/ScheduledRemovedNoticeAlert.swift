#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI

    /// The removed-occurrences notice (D442.3, D444). Undo undoes the whole save, as Edit › Undo does, and is there
    /// on iPhone, which has no Edit menu; OK is the default (UI Designer on #326). It waits for any other alert.
    struct ScheduledRemovedNoticeAlert: ViewModifier {
        let model: ScheduledListViewModel
        let presents: Bool

        private var isPresented: Binding<Bool> {
            Binding(
                get: { presents && model.alert == nil && model.removedNotice != nil },
                set: { if !$0 { model.dismissRemovedNotice() } },
            )
        }

        func body(content: Content) -> some View {
            content.alert(
                model.removedNotice?.message ?? "",
                isPresented: isPresented,
                presenting: model.removedNotice,
            ) { _ in
                Button(model.removedNoticeUndoTitle) { model.undoRemovedNotice() }
                    .accessibilityLabel(Text(model.removedNoticeUndoTitle))
                Button(model.okayTitle) { model.dismissRemovedNotice() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel(Text(model.okayTitle))
            }
        }
    }
#endif
