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
        /// A file opened from outside the app (#189), for this window's import sheet to open.
        var fileToOpen: URL?
        @ObservationIgnored private let feature: ImportExportFeature?

        public init(feature: ImportExportFeature? = nil) {
            self.feature = feature
        }

        /// File › Import… is off while a Bulk Edit, or its Undo or Redo, runs in any window (D399).
        public var importEnabled: Bool {
            feature?.importEnabled ?? true
        }
    }

    extension FocusedValues {
        /// The front window's import and export requests, for the File menu commands on Mac.
        @Entry var importExportRequests: ImportExportRequests?
    }

    /// One import session's sheet.
    private struct CSVImportSession: Identifiable {
        let id = UUID()
        let model: CSVImportViewModel
    }

    /// The import file picker, then the import sheet for the picked file, or an alert when it can't be read. A file
    /// opened from outside the app (`fileToOpen`, #189) takes the same path as a picked one.
    struct CSVImportModifier: ViewModifier {
        let feature: ImportExportFeature
        @Binding var isPicking: Bool
        @Binding var fileToOpen: URL?
        @State private var session: CSVImportSession?
        @State private var openAlert: ImportAlert?

        init(feature: ImportExportFeature, isPicking: Binding<Bool>, fileToOpen: Binding<URL?> = .constant(nil)) {
            self.feature = feature
            _isPicking = isPicking
            _fileToOpen = fileToOpen
        }

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
                // Past its file step, this import is the one D387.4's “Finish This Import First” names.
                .onChange(of: session?.id) { old, _ in
                    if let old {
                        feature.activeImports.ended(old)
                    }
                    if let session {
                        feature.activeImports.began(session.id, model: session.model)
                    }
                }
                .onChange(of: fileToOpen) { _, url in
                    guard let url else {
                        return
                    }
                    fileToOpen = nil
                    Task {
                        await open(url)
                        ExternalImportFiles.removeInboxCopy(url)
                    }
                }
                #if DEBUG
                    // Testing hook: `-LittleOrbitImportCSV <path>` opens that file here, in the first window,
                    // through the same path as a file picked in the panel.
                    .task {
                        if let url = ImportLaunchFile.take() {
                            await open(url)
                        }
                    }
                #endif
                .alert(
                    openAlert?.title ?? "",
                    isPresented: Binding(get: { openAlert != nil }, set: { if !$0 { openAlert = nil } }),
                    presenting: openAlert,
                ) { _ in
                    Button(ImportExportText.okay) {}
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
        @State private var requests: ImportExportRequests

        init(feature: ImportExportFeature) {
            self.feature = feature
            _requests = State(initialValue: ImportExportRequests(feature: feature))
        }

        func body(content: Content) -> some View {
            content
                .modifier(
                    CSVImportModifier(
                        feature: feature,
                        isPicking: $requests.isPickingImport,
                        fileToOpen: $requests.fileToOpen,
                    )
                )
                .externalImport(feature, fileToOpen: $requests.fileToOpen)
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
                .disabled(requests?.importEnabled != true)
                Button(ImportExportText.exportMenu) {
                    requests?.isExporting = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(requests == nil)
            }
        }
    }
#endif
