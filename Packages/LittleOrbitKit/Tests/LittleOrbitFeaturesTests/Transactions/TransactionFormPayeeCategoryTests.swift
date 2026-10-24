import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// #24 AC 4 on the transaction form: picking or typing payee P preselects the category last used with it,
/// never a deleted, archived or other-kind one, and never over a category chosen by hand. Names are made up.
@MainActor
@Suite("Transaction form: a payee’s last-used category")
struct TransactionFormPayeeCategoryTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    private let shopping = DefaultCategoryID.shopping
    private let food = DefaultCategoryID.food

    private func model(
        _ repository: InMemoryLedgerRepository,
        mode: TransactionFormMode = .new(accountID: F.savingsID),
    ) -> TransactionFormViewModel {
        TransactionFormViewModel(
            useCases: TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames()),
            mode: mode,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
    }

    private func repository(_ payees: [Payee], _ transactions: [Transaction] = []) throws -> InMemoryLedgerRepository {
        let repository = try F.repository()
        for payee in payees {
            try repository.savePayee(payee)
        }
        for transaction in transactions {
            try repository.saveTransaction(transaction)
        }
        return repository
    }

    @Test("Typing an existing payee’s name, in any case, reuses it and preselects its category (16:7702)")
    func typedExactName() throws {
        let parcel = Payee(name: "Parcel Point", defaultCategoryID: shopping)
        let model = model(try repository([parcel]))
        model.payeeText = "parcel point "
        #expect(model.categoryID == shopping)
        #expect(model.categoryName == "Shopping")
        #expect(model.payeeSuggestions.isEmpty)
    }

    @Test("Saving a typed existing name reuses that payee, with no duplicate (#24 v2 QA)")
    func typedNameReusedOnSave() throws {
        let parcel = Payee(name: "Parcel Point", defaultCategoryID: shopping)
        let repository = try repository([parcel])
        let model = model(repository)
        model.press(.digit(5))
        model.payeeText = "PARCEL POINT"
        #expect(model.save() != nil)
        #expect(try repository.payees().count == 1)
        let saved = try #require(try repository.transactions().first)
        #expect(saved.payeeID == parcel.id)
        #expect(saved.categoryID == shopping)
    }

    @Test("A typed partial name doesn’t preselect anything until a suggestion is picked")
    func partialName() throws {
        let parcel = Payee(name: "Parcel Point", defaultCategoryID: shopping)
        let model = model(try repository([parcel]))
        model.payeeText = "parc"
        #expect(model.categoryID == nil)
        model.choosePayee(try #require(model.payeeSuggestions.first))
        #expect(model.categoryID == shopping)
    }

    @Test("A category chosen by hand stays when a payee is picked")
    func handChosenCategoryStays() throws {
        let parcel = Payee(name: "Parcel Point", defaultCategoryID: shopping)
        let model = model(try repository([parcel]))
        model.categoryID = food
        model.payeeText = "Parcel Point"
        #expect(model.categoryID == food)
    }

    @Test("Picking another payee replaces the first payee’s preselection, or clears it if it has none")
    func anotherPayeeReplaces() throws {
        let parcel = Payee(name: "Parcel Point", defaultCategoryID: shopping)
        let bakery = Payee(name: "Corner Bakery", defaultCategoryID: food)
        let fresh = Payee(name: "Green Basket")
        let model = model(try repository([parcel, bakery, fresh]))
        model.payeeText = "Parcel Point"
        #expect(model.categoryID == shopping)
        model.payeeText = "Corner Bakery"
        #expect(model.categoryID == food)
        model.payeeText = "Green Basket"
        #expect(model.categoryID == nil, "Food & Dining was only Corner Bakery’s")
    }

    @Test("An archived last-used category isn’t preselected, and nothing crashes (#24 design notes)")
    func archivedCategory() throws {
        let parcel = Payee(name: "Parcel Point", defaultCategoryID: shopping)
        let repository = try repository([parcel])
        try repository.archiveCategory(id: shopping, archived: true)
        let model = model(repository)
        model.payeeText = "Parcel Point"
        #expect(model.categoryID == nil)
        #expect(model.categoryName == "Uncategorised")
    }

    @Test("A payee whose last-used category was deleted preselects nothing (#11 nullify)")
    func deletedCategory() throws {
        let repository = try repository([])
        let pets = try CategoryUseCases(repository: repository).saveCategory
            .add(
                named: "Pet care",
                kind: .expense,
                parentID: nil,
            )
        let parcel = Payee(name: "Parcel Point", defaultCategoryID: pets.id)
        try repository.savePayee(parcel)
        try CategoryUseCases(repository: repository).deleteCategory.delete(pets.id, choice: .leaveUncategorised)
        let model = model(repository)
        model.payeeText = "Parcel Point"
        #expect(model.categoryID == nil)
    }

    @Test("An expense category isn’t preselected on income")
    func otherKind() throws {
        let parcel = Payee(name: "Parcel Point", defaultCategoryID: shopping)
        let model = model(try repository([parcel]))
        model.type = .income
        model.payeeText = "Parcel Point"
        #expect(model.categoryID == nil)
    }

    @Test("Opening an uncategorised transaction with a payee changes nothing until something is edited")
    func editOpensUnchanged() throws {
        let parcel = Payee(name: "Parcel Point", defaultCategoryID: shopping)
        let original = F.expense(40, on: F.date(2026, 10, 19), payee: parcel.id)
        let model = model(try repository([parcel], [original]), mode: .edit(original.id))
        #expect(model.categoryID == nil)
        #expect(!model.hasUnsavedInput)
    }
}
