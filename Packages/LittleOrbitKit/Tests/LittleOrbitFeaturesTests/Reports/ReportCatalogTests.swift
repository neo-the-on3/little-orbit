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
            "This Year", "Last Year", "Last 6 Months", "%1$@ › %2$@", "Spent in %1$@ · %2$@ · %3$@", "all accounts",
            "Hidden",
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

    @Test("The chart's Other bar plurals its count, visibly and for VoiceOver (#184 slice 3)")
    func otherPlural() throws {
        let entries = try StringCatalogTests.entries()
        #expect(
            Set(try #require(entries["Other · %lld categories"])) == [
                "Other · %lld category", "Other · %lld categories",
            ]
        )
        #expect(
            Set(try #require(entries["Other, %lld categories"])) == ["Other, %lld category", "Other, %lld categories"]
        )
    }

    @Test("The audio graph's name for a repeated bar name is one entry with its English value (#310 n1)")
    func repeatedBarName() throws {
        #expect(try StringCatalogTests.entries()["%1$@ (%2$lld)"] == ["%1$@ (%2$lld)"])
    }

    @Test("The Mac table's column titles are their own keys, apart from the shared Category, Amount and Transactions")
    func tableColumns() throws {
        let entries = try StringCatalogTests.entries()
        #expect(entries["report.column.category"] == ["Category"])
        #expect(entries["report.column.transactions"] == ["Transactions"])
        #expect(entries["report.column.amount"] == ["Amount"])
        #expect(entries["report.column.share"] == ["Share"])
    }

    @Test("The payee report's wording is in the catalog, its Other bar plurals and Payee is its own key (#184 slice 4)")
    func payeeEntries() throws {
        let entries = try StringCatalogTests.entries()
        for key in [
            "Where do I spend the most?", "Spending by Payee", "All Payees", "No Payee",
            "Sorted by amount. Refunds reduce spending at their payee. Transfers between your accounts aren’t spending.",
        ] {
            #expect(entries[key] == [key], "\(key) is one entry with its English value")
        }
        #expect(Set(try #require(entries["Other · %lld payees"])) == ["Other · %lld payee", "Other · %lld payees"])
        #expect(Set(try #require(entries["Other, %lld payees"])) == ["Other, %lld payee", "Other, %lld payees"])
        #expect(entries["report.column.payee"] == ["Payee"])
    }

    @Test(
        "The income report's wording is in the catalog, its Other bar plurals and its title is its own key (#184 slice 5)"
    )
    func incomeEntries() throws {
        let entries = try StringCatalogTests.entries()
        for key in [
            "Where does my money come from?", "Earned in %1$@ · %2$@ · %3$@", "Sources of Income", "%1$@ of income",
            "Sorted by amount. Refunds and transfers between your accounts aren’t income.", "No Income",
            "There’s no income in this period. Try another period.",
        ] {
            #expect(entries[key] == [key], "\(key) is one entry with its English value")
        }
        #expect(Set(try #require(entries["Other · %lld sources"])) == ["Other · %lld source", "Other · %lld sources"])
        #expect(Set(try #require(entries["Other, %lld sources"])) == ["Other, %lld source", "Other, %lld sources"])
        #expect(entries["report.title.income"] == ["Income"])
    }

    @Test("The transaction count has one and other variants, each with %lld")
    func countPlural() throws {
        let values = try #require(try StringCatalogTests.entries()["%lld transactions"])
        #expect(Set(values) == ["%lld transaction", "%lld transactions"])
    }
}
