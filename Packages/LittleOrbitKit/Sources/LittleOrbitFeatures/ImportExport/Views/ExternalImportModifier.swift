#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI

    /// A CSV file opened from outside the app (#189 I9 to I13): iOS Open in and the share sheet, and the Mac Dock,
    /// Finder and window drop. It's handed to `fileToOpen`, the window's import sheet's own open path, so it's read,
    /// and a Debit & Credit file detected, as when it's picked there (D439.2), and a refused file gets that path's
    /// alerts (D451.3). `ExternalImportRoute` decides; `ExternalImportEvents` makes one open event one import sheet,
    /// in one window, though every main window has these handlers (Tech Architect on #339).
    struct ExternalImportModifier: ViewModifier {
        let feature: ImportExportFeature
        @Binding var fileToOpen: URL?
        @Environment(OpenSheets.self) private var sheets: OpenSheets?
        #if os(macOS)
            /// Whether this window is the key window.
            @Environment(\.appearsActive) private var appearsActive
            @State private var isDropTargeted = false
        #endif
        /// This window, for `ExternalImportEvents`.
        @State private var window = UUID()
        /// A file waiting for this window's sheets to close (D387.4, D451.1, I12).
        @State private var pending = ExternalImportRoute.Pending()
        @State private var alert: ImportAlert?

        func body(content: Content) -> some View {
            content
                .onOpenURL { url in
                    feature.externalEvents.post([url], from: window)
                }
                .onChange(of: feature.externalEvents.pending?.id) {
                    take()
                }
                .onAppear {
                    feature.externalEvents.windowAppeared(window)
                    #if os(macOS)
                        if appearsActive {
                            feature.externalEvents.windowBecameKey(window)
                        }
                    #endif
                    take()
                }
                .onDisappear {
                    feature.externalEvents.windowClosed(window)
                }
                #if os(macOS)
                    .onChange(of: appearsActive) { _, isKey in
                        if isKey {
                            feature.externalEvents.windowBecameKey(window)
                            take()
                        }
                    }
                    // A drop is for the window it lands on, so it doesn't wait for the key window.
                    .dropDestination(for: URL.self) { urls, _ in
                        receive(urls)
                    } isTargeted: { isTargeted in
                        isDropTargeted = isTargeted
                    }
                    .overlay {
                        if isDropTargeted {
                            DropHighlight()
                        }
                    }
                #endif
                // Driven by the sheet count, not a timer (Tech Architect on #339).
                .onChange(of: sheets?.count ?? 0) { _, count in
                    if let url = pending.sheetsChanged(to: count) {
                        receive([url])
                    }
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

        private func take() {
            if let urls = feature.externalEvents.take(for: window) {
                receive(urls)
            }
        }

        /// Routes `urls`; `false` when there was nothing to open, such as a web link.
        @discardableResult
        private func receive(_ urls: [URL]) -> Bool {
            let route = ExternalImportRoute.route(
                urls,
                importInProgress: feature.activeImports.inProgress,
                hasUnsavedEdits: sheets?.hasUnsavedEdits ?? false,
            )
            switch pending.receive(route, sheetsOpen: sheets?.count ?? 0) {
            case .present(let url):
                fileToOpen = url
            case .closeSheetsThenPresent:
                // Untouched sheets close, newest first, as for a tapped reminder (S33, D451.1). The count reaching
                // zero opens the import.
                _ = sheets?.prepareForReminder()
            case .wait:
                break
            case .showAlert:
                alert = route.alert
            case .nothing:
                return false
            }
            return true
        }
    }

    #if os(macOS)
        /// The outline while a file is dragged over a window (UI Designer on #339): the accent colour, about 3 pt,
        /// inset from the content's edges, with no fill and no animation of its own. The system draws the cursor's
        /// plus badge.
        private struct DropHighlight: View {
            var body: some View {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    #endif

    extension View {
        /// Opens a CSV file handed over from outside the app in this window's import sheet (#189).
        func externalImport(_ feature: ImportExportFeature, fileToOpen: Binding<URL?>) -> some View {
            modifier(ExternalImportModifier(feature: feature, fileToOpen: fileToOpen))
        }
    }
#endif
