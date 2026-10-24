import Foundation
import LittleOrbitDomain
import Testing

/// D292: new stores are seeded with the approved PR #51 symbols, one per built-in category.
@Suite("Default category symbols (D292)")
struct DefaultCategorySymbolTests {
    @Test("D292: every built-in category is seeded with its PR #51 symbol")
    func seedSymbols() {
        let expected: [UUID: String] = [
            DefaultCategoryID.food: "fork.knife",
            DefaultCategoryID.groceries: "cart.fill",
            DefaultCategoryID.transport: "car.fill",
            DefaultCategoryID.housing: "house.fill",
            DefaultCategoryID.utilities: "bolt.fill",
            DefaultCategoryID.health: "cross.case.fill",
            DefaultCategoryID.insurance: "umbrella.fill",
            DefaultCategoryID.shopping: "bag.fill",
            DefaultCategoryID.entertainment: "popcorn.fill",
            DefaultCategoryID.personal: "person.fill",
            DefaultCategoryID.education: "graduationcap.fill",
            DefaultCategoryID.travel: "airplane",
            DefaultCategoryID.fees: "doc.text.fill",
            DefaultCategoryID.otherExpense: "ellipsis.circle.fill",
            DefaultCategoryID.salary: "briefcase.fill",
            DefaultCategoryID.interest: "percent",
            DefaultCategoryID.gifts: "gift.fill",
            DefaultCategoryID.otherIncome: "plus.circle.fill",
        ]
        let seeded = DefaultCategories.make(names: TestCategoryNames())
        #expect(seeded.count == 18)
        #expect(Dictionary(uniqueKeysWithValues: seeded.map { ($0.id, $0.iconName ?? "") }) == expected)
        #expect(Set(expected.values).count == 18)
    }
}
