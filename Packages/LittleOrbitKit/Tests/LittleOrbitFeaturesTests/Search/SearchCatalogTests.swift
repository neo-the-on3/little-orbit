import Foundation
import Testing

/// Search's wording is in the String Catalog, and each plural variant fills its count (#28).
@Suite("Search String Catalog")
struct SearchCatalogTests {
    static let keys = [
        "Search transactions", "All", "Transfers", "Net", "Moved between your accounts",
        "Upcoming matches are listed but not counted.", "Use YYYY-MM-DD", "Clear Search", "No Results for “%@”",
        "Check the spelling or try fewer words. Search looks at description, category, payee, tag and notes.",
        "No Transactions", "Transactions you add will appear here.", "Couldn’t Load Transactions", "Try again.",
        "%@ moved", "Upcoming, %1$@, %2$@", "To %@", "From %@", "Export CSV…", "Export CSV", "Refund · %@",
        "Refund (original deleted) · %@", "Refund", "Refund (original deleted)",
    ]

    /// Search's own keys for words other screens also use, and their English text (Tech Architect NB5).
    static let contextKeys = [
        "search.scope.expenses": "Expenses", "search.scope.income": "Income",
        "search.total.expenses": "Expenses", "search.total.income": "Income",
        "search.row.expense": "Expense", "search.row.income": "Income",
        "search.column.description": "Description", "search.column.payee": "Payee",
    ]

    @Test("Every search string has a catalog entry")
    func entries() throws {
        let entries = try StringCatalogTests.entries()
        for key in Self.keys {
            #expect(entries[key] != nil, "Missing \(key)")
        }
    }

    @Test("D320: the settled wording replaced the drafts, which are gone from the catalog")
    func settledWording() throws {
        let entries = try StringCatalogTests.entries()
        for key in [
            "No results for “%@”", "Transactions you add show here.", "Couldn’t load transactions. Try again.",
            "Expenses",
        ] {
            #expect(entries[key] == nil, "Unused \(key)")
        }
    }

    @Test("NB5: the scope bar, summary totals and row titles have their own keys, apart from the category kinds")
    func contextKeys() throws {
        let entries = try StringCatalogTests.entries()
        for (key, english) in Self.contextKeys {
            #expect(entries[key] == [english], "\(key) reads \(english)")
        }
    }

    @Test("The count and upcoming-note plurals have one and other forms that both use %lld (D134)")
    func plurals() throws {
        let entries = try StringCatalogTests.entries()
        for key in ["%lld results", "%lld upcoming matches are listed but not counted."] {
            let values = try #require(entries[key])
            #expect(values.count == 2, "\(key) has one and other")
            #expect(values.allSatisfy { $0.contains("%lld") }, "\(key) fills its count")
        }
    }

    @Test("D325.1: the iOS row has its own Export CSV entry with no ellipsis, apart from the macOS button")
    func exportLabels() throws {
        let entries = try StringCatalogTests.entries()
        #expect(entries["Export CSV"] == ["Export CSV"])
        #expect(entries["Export CSV…"] == ["Export CSV…"])
    }
}
