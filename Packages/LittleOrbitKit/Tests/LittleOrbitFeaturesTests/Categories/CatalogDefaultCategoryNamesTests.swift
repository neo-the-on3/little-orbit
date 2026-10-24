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

    @Test("Every built-in category name is its own category.seed key with its English value, no bare English key")
    func catalogEntries() throws {
        let entries = try StringCatalogTests.entries()
        let keys: [DefaultCategory: String] = [
            .food: "food", .groceries: "groceries", .transport: "transport", .housing: "housing",
            .utilities: "utilities", .health: "health", .insurance: "insurance", .shopping: "shopping",
            .entertainment: "entertainment", .personal: "personalCare", .education: "education",
            .travel: "travel", .fees: "fees", .otherExpense: "otherExpense", .salary: "salary",
            .interest: "interest", .gifts: "giftsReceived", .otherIncome: "otherIncome",
        ]
        for category in DefaultCategory.allCases {
            let name = try #require(english[category])
            let key = "category.seed.\(try #require(keys[category]))"
            #expect(entries[key] == [name], "\(key) is missing from the catalog")
            #expect(entries[name] == nil, "\(name) is still a bare key")
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
