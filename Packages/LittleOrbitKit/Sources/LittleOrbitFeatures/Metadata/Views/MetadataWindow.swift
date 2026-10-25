#if canImport(SwiftUI) && os(macOS)
    import SwiftUI

    /// The Mac Metadata manager (#24 part 5): its own window, opened from the app menu, with a Categories /
    /// Payees switch in the toolbar (no Descriptions in the MVP, D304). The window remembers the last tab. It
    /// reloads when another window changes the ledger, so the Used counts stay current.
    public struct MetadataWindow: View {
        /// The window scene's id, for `openWindow(id:)`.
        public static let id = "metadata"

        @State private var categories: MetadataCategoriesViewModel
        @State private var payees: MetadataPayeesViewModel
        @SceneStorage("metadata.tab") private var tab: MetadataTab = .categories
        private let updates: LedgerUpdates

        public init(categories: CategoriesFeature, payees: PayeesFeature, updates: LedgerUpdates) {
            _categories = State(initialValue: MetadataCategoriesViewModel(screen: categories.makeScreen()))
            _payees = State(initialValue: MetadataPayeesViewModel(screen: payees.makeScreen()))
            self.updates = updates
        }

        /// The window's title.
        public static var title: String {
            MetadataText.windowTitle
        }

        public var body: some View {
            Group {
                switch tab {
                case .categories:
                    MetadataCategoriesView(model: categories)
                case .payees:
                    MetadataPayeesView(model: payees)
                }
            }
            .frame(minWidth: 600, idealWidth: 720, minHeight: 420, idealHeight: 520)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker(MetadataText.show, selection: $tab) {
                        Text(CategoryText.title).tag(MetadataTab.categories)
                        Text(PayeeText.title).tag(MetadataTab.payees)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .onAppear(perform: load)
            .onChange(of: updates.revision, load)
        }

        private func load() {
            categories.load()
            payees.load()
        }
    }

    /// The Metadata window's tabs.
    enum MetadataTab: String {
        case categories
        case payees
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
