import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// The category picker groups each parent with its subcategories, one section each (UI Designer, #87).
@MainActor
@Suite("Category picker sections")
struct TransactionCategoryGroupTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    private func option(_ name: String, parent: TransactionCategoryOption? = nil) -> TransactionCategoryOption {
        TransactionCategoryOption(
            id: UUID(),
            name: name,
            symbolName: "tag",
            isSubcategory: parent != nil,
            parentID: parent?.id,
        )
    }

    @Test("Each parent leads its section with its subcategories in order; a lone subcategory is its own")
    func grouping() {
        let food = option("Food")
        let groceries = option("Groceries", parent: food)
        let dining = option("Dining Out", parent: food)
        let transport = option("Transport")
        let archivedParent = TransactionCategoryOption(
            id: UUID(),
            name: "Hobbies",
            symbolName: "tag",
            isSubcategory: false,
        )
        let lone = option("Books", parent: archivedParent)
        let groups = TransactionCategoryGroup.groups([food, groceries, dining, transport, lone])
        #expect(groups.map(\.parent.name) == ["Food", "Transport", "Books"])
        #expect(groups[0].subcategories.map(\.name) == ["Groceries", "Dining Out"])
        #expect(groups[1].subcategories.isEmpty)
        #expect(groups[2].subcategories.isEmpty, "Its parent isn't offered")
    }

    @Test("The entry sheet's sections hold every option once, parents first, in the picker's order")
    func entrySheet() throws {
        let model = TransactionFormViewModel(
            useCases: TransactionUseCases(
                repository: try F.repository(),
                categoryNames: CatalogDefaultCategoryNames(),
            ),
            mode: .new(accountID: F.savingsID),
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
        let groups = model.categoryGroups
        #expect(groups.flatMap { [$0.parent] + $0.subcategories } == model.categoryOptions)
        #expect(groups.allSatisfy { !$0.parent.isSubcategory })
        #expect(groups.allSatisfy { group in group.subcategories.allSatisfy { $0.parentID == group.parent.id } })
        #expect(groups.contains { !$0.subcategories.isEmpty }, "The default categories have subcategories")
    }

    @Test("Bulk edit's sections group each subcategory under its parent too, every option once")
    func bulkEdit() throws {
        let rows = [F.expense(100, on: F.date(2026, 10, 15)), F.expense(200, on: F.date(2026, 10, 16))]
        let model = BulkEditViewModel(
            useCases: TransactionUseCases(
                repository: try F.repository(rows),
                categoryNames: CatalogDefaultCategoryNames(),
            ),
            transactionIDs: rows.map(\.id),
            locale: F.india,
            timeZone: F.zone,
        )
        let groups = model.categoryGroups
        let flattened = groups.flatMap { [$0.parent] + $0.subcategories }
        #expect(flattened.count == model.categoryOptions.count)
        #expect(Set(flattened.map(\.id)) == Set(model.categoryOptions.map(\.id)))
        #expect(groups.allSatisfy { !$0.parent.isSubcategory })
        #expect(groups.allSatisfy { group in group.subcategories.allSatisfy { $0.parentID == group.parent.id } })
        #expect(groups.contains { !$0.subcategories.isEmpty })
    }

    @Test("VoiceOver's value, read once: Uncategorised, a parent, or a subcategory with its parent (both pickers)")
    func spokenValue() throws {
        let rows = [F.expense(100, on: F.date(2026, 10, 15)), F.expense(200, on: F.date(2026, 10, 16))]
        let useCases = TransactionUseCases(
            repository: try F.repository(rows),
            categoryNames: CatalogDefaultCategoryNames(),
        )
        let form = TransactionFormViewModel(
            useCases: useCases,
            mode: .new(accountID: F.savingsID),
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
        let bulk = BulkEditViewModel(
            useCases: useCases,
            transactionIDs: rows.map(\.id),
            locale: F.india,
            timeZone: F.zone,
        )
        let group = try #require(form.categoryGroups.first { !$0.subcategories.isEmpty })
        let child = try #require(group.subcategories.first)
        let bulkGroup = try #require(bulk.categoryGroups.first { !$0.subcategories.isEmpty })
        let bulkChild = try #require(bulkGroup.subcategories.first)

        form.categoryID = nil
        bulk.categoryID = nil
        #expect(form.categorySpokenValue == "Uncategorised")
        #expect(bulk.categorySpokenValue == "Uncategorised")
        #expect(bulk.categoryName == "Uncategorised")

        form.categoryID = group.parent.id
        bulk.categoryID = bulkGroup.parent.id
        #expect(form.categorySpokenValue == group.parent.name)
        #expect(bulk.categorySpokenValue == bulkGroup.parent.name)

        form.categoryID = child.id
        bulk.categoryID = bulkChild.id
        #expect(form.categoryName == child.name, "The picker shows the name alone")
        #expect(form.categorySpokenValue == "\(child.name), under \(group.parent.name)")
        #expect(bulk.categoryName == bulkChild.name)
        #expect(bulk.categorySpokenValue == "\(bulkChild.name), under \(bulkGroup.parent.name)")

        // The picker reads its value once (Tester's #87 v11): the spoken value is the only place the name goes.
        #expect(occurrences(of: child.name, in: form.categorySpokenValue) == 1)
        #expect(occurrences(of: bulkChild.name, in: bulk.categorySpokenValue) == 1)
        form.categoryID = group.parent.id
        #expect(occurrences(of: group.parent.name, in: form.categorySpokenValue) == 1)
    }

    private func occurrences(of name: String, in text: String) -> Int {
        text.components(separatedBy: name).count - 1
    }
}
