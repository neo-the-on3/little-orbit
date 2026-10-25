#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI

    extension View {
        /// Lists this sheet's content in the window's `OpenSheets` while it's shown, so a tapped reminder closes it
        /// first when `hasUnsavedEdits` is false and leaves it open otherwise (S33). Without `OpenSheets` in the
        /// environment it does nothing.
        public func openSheet(
            hasUnsavedEdits: @escaping @MainActor () -> Bool,
            close: @escaping @MainActor () -> Void,
        ) -> some View {
            modifier(OpenSheetModifier(hasUnsavedEdits: hasUnsavedEdits, close: close))
        }
    }

    private struct OpenSheetModifier: ViewModifier {
        let hasUnsavedEdits: @MainActor () -> Bool
        let close: @MainActor () -> Void
        @Environment(OpenSheets.self) private var sheets: OpenSheets?
        @State private var id = UUID()

        func body(content: Content) -> some View {
            content
                .onAppear { sheets?.opened(id, hasUnsavedEdits: hasUnsavedEdits, close: close) }
                .onDisappear { sheets?.closed(id) }
        }
    }
#endif
