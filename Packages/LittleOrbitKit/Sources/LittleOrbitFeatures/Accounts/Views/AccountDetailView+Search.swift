#if canImport(SwiftUI) && os(iOS)
    import LittleOrbitTheme
    import SwiftUI

    /// Search results for one account, each transfer from its side (D25), laid out as the search screen lays
    /// them out: hints, the summary, then each day. `row` draws a result as the history draws it, so a tap edits.
    struct AccountSearchResults<Row: View>: View {
        let search: TransactionSearchViewModel
        @ViewBuilder let row: (TransactionRowModel) -> Row

        var body: some View {
            if !search.hints.isEmpty {
                Section {
                    ForEach(search.hints, id: \.self) { hint in
                        Label(hint, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color(ThemeColor.labelSecondary))
                    }
                }
            }
            if let summary = search.summary {
                Section { SearchSummaryView(summary: summary, note: search.upcomingNote) }
            }
            if search.isNoResults {
                Section {
                    ContentUnavailableView {
                        Label(search.noResultsTitle, systemImage: "magnifyingglass")
                    } description: {
                        Text(search.noResultsMessage)
                    }
                }
            }
            ForEach(search.sections) { section in
                Section {
                    ForEach(section.rows) { row($0) }
                } header: {
                    SearchDayHeader(section: section)
                }
            }
        }
    }

    /// The search field hidden above an account's history until the list is pulled down (#28 iOS platforms,
    /// D322.2): the system's `navigationBarDrawer` with `.automatic`. Typing searches after a short pause.
    struct AccountSearchField: ViewModifier {
        let search: TransactionSearchViewModel?

        func body(content: Content) -> some View {
            if let search {
                content
                    .searchable(
                        text: Binding(get: { search.query }, set: { search.query = $0 }),
                        placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: Text(search.prompt),
                    )
                    .task(id: search.query) {
                        do {
                            try await Task.sleep(for: .milliseconds(200))
                        } catch {
                            return
                        }
                        guard !search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            return
                        }
                        search.load()
                    }
            } else {
                content
            }
        }
    }
#endif
