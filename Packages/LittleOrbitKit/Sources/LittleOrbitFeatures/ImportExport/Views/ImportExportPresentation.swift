#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitDomain
    import Observation
    import SwiftUI

    /// What a window was asked to show: the import file picker or the export sheet. Each window has its own, so
    /// a menu command only opens in the window in front.
    @MainActor
    @Observable
    public final class ImportExportRequests {
        public var isPickingImport = false
        public var isExporting = false

        public init() {}
    }

    extension FocusedValues {
        /// The front window's import and export requests, for the File menu commands on Mac.
        @Entry var importExportRequests: ImportExportRequests?
    }

    /// The OK that closes an import or export alert. Its title is also its accessibility name, which a plain
    /// alert button didn't expose on the Mac (Tester's #190 Mac pass).
    struct ImportAlertOKButton: View {
        var body: some View {
            Button {
            } label: {
                Text(ImportExportText.okay)
            }
            .accessibilityLabel(Text(ImportExportText.okay))
        }
    }

    /// One import session's sheet.
    private struct CSVImportSession: Identifiable {
        let id = UUID()
        let model: CSVImportViewModel
    }

    /// The import file picker, then the import sheet for the picked file, or an alert when it can't be read.
    struct CSVImportModifier: ViewModifier {
        let feature: ImportExportFeature
        @Binding var isPicking: Bool
        @State private var session: CSVImportSession?
        @State private var openAlert: ImportAlert?

        func body(content: Content) -> some View {
            content
                .fileImporter(isPresented: $isPicking, allowedContentTypes: CSVImportTypes.all) { result in
                    guard case .success(let url) = result else {
                        return
                    }
                    Task { await open(url) }
                }
                .sheet(item: $session) { session in
                    CSVImportSheet(model: session.model, feature: feature)
                }
                .alert(
                    openAlert?.title ?? "",
                    isPresented: Binding(get: { openAlert != nil }, set: { if !$0 { openAlert = nil } }),
                    presenting: openAlert,
                ) { _ in
                    ImportAlertOKButton()
                } message: { alert in
                    Text(alert.message)
                }
        }

        private func open(_ url: URL) async {
            let model = feature.makeImport()
            await model.open(url: url)
            if model.step == .pickFile {
                openAlert = model.alert
            } else {
                session = CSVImportSession(model: model)
            }
        }
    }

    /// CSV import and export for one window: the picker, the sheets, and the requests the File menu sends.
    struct ImportExportPresenter: ViewModifier {
        let feature: ImportExportFeature
        @State private var requests = ImportExportRequests()

        func body(content: Content) -> some View {
            content
                .modifier(CSVImportModifier(feature: feature, isPicking: $requests.isPickingImport))
                .sheet(isPresented: $requests.isExporting) {
                    CSVExportSheet(feature: feature)
                }
                .focusedSceneValue(\.importExportRequests, requests)
        }
    }

    extension View {
        /// Adds CSV import and export to a window: the File menu commands on Mac reach it through the focused
        /// scene.
        public func importExport(_ feature: ImportExportFeature) -> some View {
            modifier(ImportExportPresenter(feature: feature))
        }
    }

    /// File › Import… (⇧⌘I) and Export Transactions… (⇧⌘E) on Mac, for the window in front (D323.9).
    public struct ImportExportCommands: Commands {
        @FocusedValue(\.importExportRequests) private var requests

        public init() {}

        public var body: some Commands {
            CommandGroup(after: .importExport) {
                Button(ImportExportText.importMenu) {
                    requests?.isPickingImport = true
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(requests == nil)
                Button(ImportExportText.exportMenu) {
                    requests?.isExporting = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(requests == nil)
            }
        }
    }
#endif
