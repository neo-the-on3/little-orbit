import Foundation
import Testing

/// The spending report's wording is in the String Catalog, each entry with its English value, and the
/// transaction count keeps its one/other variants with %lld.
@Suite("Spending report String Catalog entries (#27 core)")
struct ReportCatalogTests {
    @Test("Every report key is a catalog entry whose English value is the key")
    func entries() throws {
        let entries = try StringCatalogTests.entries()
        let keys = [
            "Reports", "Spending", "What do I spend my money on?", "Period", "Currency", "This Month", "Last Month",
            "This Quarter", "Last Quarter", "%1$@ · %2$@ · %3$@", "%1$lld of %2$lld", "Both dates are included.",
            "Only %1$@ accounts are listed because the report shows %1$@.",
            "This Year", "Last Year", "%1$@ › %2$@", "Spent in %1$@ · %2$@ · %3$@", "all accounts", "Hidden",
            "Custom…", "Previous Period", "Next Period", "%1$@ · %2$@", "%1$@ of spending",
            "All Categories", "No Expenses", "There are no expenses in this period. Try another period.",
            "Couldn’t Load Report", "Refund", "Refund · %@", "Refund (original deleted)",
            "Refund (original deleted) · %@", "Uncategorised", "Try again.", "Expense",
            "Sorted by amount. Refunds reduce spending in their category. Transfers between your accounts aren’t spending.",
        ]
        for key in keys {
            #expect(entries[key] == [key], "\(key) is one entry with its English value")
        }
        for gone in [
            "No spending in %@", "%1$@ of spending · %2$@", "Spent in %1$@ · %2$@", "Custom Range", "Q%1$lld %2$@",
            "%1$@ – %2$@",
            "Sorted by amount. Refunds reduce spending in their category. Transfers between your accounts aren’t spending. Future-dated items aren’t included.",
        ] {
            #expect(entries[gone] == nil, "\(gone) is no longer used (D318.4, D319.5, D319.6, #184)")
        }
    }

    @Test("The Accounts row's “All” is its own key, so it can't clash with another “All”")
    func accountsAll() throws {
        #expect(try StringCatalogTests.entries()["report.accounts.all"] == ["All"])
    }

    @Test("“2 of 3 accounts” plurals the total through a substitution (UI Designer's slice 1 spec)")
    func accountsOfPlural() throws {
        let values = try #require(try StringCatalogTests.entries()["%1$lld of %2$lld accounts"])
        #expect(Set(values) == ["%1$lld of %#@total@", "%arg account", "%arg accounts"])
    }

    @Test("The transaction count has one and other variants, each with %lld")
    func countPlural() throws {
        let values = try #require(try StringCatalogTests.entries()["%lld transactions"])
        #expect(Set(values) == ["%lld transaction", "%lld transactions"])
    }
}
