import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The built-in category names come from the String Catalog (D8), keep their fixed ids, and match the PR #51
/// seed list.
@Suite("Default category names (D8)")
@MainActor
struct CatalogDefaultCategoryNamesTests {
    private let names = CatalogDefaultCategoryNames()

    private let english: [DefaultCategory: String] = [
        .food: "Food & Dining", .groceries: "Groceries", .transport: "Transport", .housing: "Housing",
        .utilities: "Utilities", .health: "Health", .insurance: "Insurance", .shopping: "Shopping",
        .entertainment: "Entertainment", .personal: "Personal Care", .education: "Education", .travel: "Travel",
        .fees: "Fees & Charges", .otherExpense: "Other", .salary: "Salary", .interest: "Interest",
        .gifts: "Gifts Received", .otherIncome: "Other Income",
    ]

    @Test("Every built-in category has its English name")
    func englishNames() {
        for category in DefaultCategory.allCases {
            #expect(names.name(of: category) == english[category], "\(category)")
        }
    }

    @Test("Every built-in category name is a String Catalog entry with its English value")
    func catalogEntries() throws {
        let entries = try StringCatalogTests.entries()
        for category in DefaultCategory.allCases {
            let key = try #require(english[category])
            #expect(entries[key] == [key], "\(key) is missing from the catalog")
        }
    }

    @Test("Seeding on first entry stores the catalog names under the fixed ids")
    func seededNames() throws {
        let repository = InMemoryLedgerRepository()
        let useCases = TransactionUseCases(repository: repository, categoryNames: names)
        let categories = try useCases.loadLedger.ledgerForEntry().categories
        #expect(categories.count == DefaultCategory.allCases.count)
        for category in DefaultCategory.allCases {
            #expect(categories.first { $0.id == category.id }?.name == english[category])
        }
        #expect(
            categories.first { $0.id == DefaultCategoryID.food }?.id.uuidString
                == "E1E10000-0000-4000-8000-000000000001"
        )
    }
}
