#if canImport(SwiftUI) && os(macOS)
    import SwiftUI

    /// The Mac Metadata manager (#24 part 5): its own window, opened from the app menu, for Categories. It
    /// reloads when another window changes the ledger, so the Used counts stay current.
    public struct MetadataWindow: View {
        /// The window scene's id, for `openWindow(id:)`.
        public static let id = "metadata"

        @State private var model: MetadataCategoriesViewModel
        private let updates: LedgerUpdates

        public init(categories: CategoriesFeature, updates: LedgerUpdates) {
            _model = State(initialValue: MetadataCategoriesViewModel(screen: categories.makeScreen()))
            self.updates = updates
        }

        /// The window's title.
        public static var title: String {
            MetadataText.windowTitle
        }

        public var body: some View {
            MetadataCategoriesView(model: model)
                .frame(minWidth: 600, idealWidth: 720, minHeight: 420, idealHeight: 520)
                .onAppear { model.load() }
                .onChange(of: updates.revision) { model.load() }
        }
    }

    /// The app menu's Metadata… item, after Settings…, which opens or brings forward the Metadata window.
    public struct MetadataCommand: Commands {
        @Environment(\.openWindow) private var openWindow

        public init() {}

        public var body: some Commands {
            CommandGroup(after: .appSettings) {
                Button(MetadataText.windowTitle) {
                    openWindow(id: MetadataWindow.id)
                }
            }
        }
    }
#endif
