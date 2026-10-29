#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI

    /// A CSV file opened from outside the app (#189 I9 to I13): iOS Open in and the share sheet, and the Mac Dock,
    /// Finder and window drop. It's handed to `fileToOpen`, the window's import sheet's own open path, so it's read,
    /// and a Debit & Credit file detected, as when it's picked there (D439.2). `ExternalImportRoute` decides.
    struct ExternalImportModifier: ViewModifier {
        let feature: ImportExportFeature
        @Binding var fileToOpen: URL?
        @Environment(OpenSheets.self) private var sheets: OpenSheets?
        /// A file waiting for this window's sheets to close (D387.4, I12).
        @State private var waiting: URL?
        @State private var alert: ImportAlert?

        func body(content: Content) -> some View {
            content
                .onOpenURL { url in
                    receive([url])
                }
                #if os(macOS)
                    // A Dock or Finder open goes to a window that's already open, not a new one.
                    .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                    .dropDestination(for: URL.self) { urls, _ in
                        receive(urls)
                        return true
                    }
                #endif
                .onChange(of: sheets?.count ?? 0) { _, count in
                    guard count == 0, let url = waiting else {
                        return
                    }
                    waiting = nil
                    receive([url])
                }
                .alert(
                    alert?.title ?? "",
                    isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } }),
                    presenting: alert,
                ) { _ in
                    Button(ImportExportText.okay) {}
                } message: { alert in
                    Text(alert.message)
                }
        }

        private func receive(_ urls: [URL]) {
            let route = ExternalImportRoute.route(
                urls,
                importInProgress: feature.activeImports.inProgress,
                hasUnsavedEdits: sheets?.hasUnsavedEdits ?? false,
            )
            switch route {
            case .open(let url):
                // Untouched sheets close first, newest first, as for a tapped reminder (S33); the import opens
                // once they're gone.
                if let sheets, sheets.count > 0 {
                    waiting = url
                    _ = sheets.prepareForReminder()
                } else {
                    fileToOpen = url
                }
            case .afterSheetsClose(let url):
                waiting = url
            case .finishImportFirst, .oneFileAtATime:
                alert = route.alert
            case .ignore:
                break
            }
        }
    }

    extension View {
        /// Opens a CSV file handed over from outside the app in this window's import sheet (#189).
        func externalImport(_ feature: ImportExportFeature, fileToOpen: Binding<URL?>) -> some View {
            modifier(ExternalImportModifier(feature: feature, fileToOpen: fileToOpen))
        }
    }
#endif
