import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// #215 (D446, D368.2): a typed Received is in To's currency, so moving To to another currency clears it, the same
/// rule as #207's scheduled form. Checks 1, 2, 4 and 6 are the merge gate (D285.5). Made-up data only: Everyday
/// Savings (INR), Travel Wallet (USD), Dollar Card (USD), Euro Card (EUR) and Cash (INR); today is 20 Oct 2026.
@MainActor
@Suite("Transaction form: Received follows To's currency (#215)")
struct TransactionReceivedCurrencyTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    static let travelID = UUID(uuidString: "21500000-0000-4000-8000-000000000001")!
    static let dollarID = UUID(uuidString: "21500000-0000-4000-8000-000000000002")!
    static let euroID = UUID(uuidString: "21500000-0000-4000-8000-000000000003")!
    static let cashID = UUID(uuidString: "21500000-0000-4000-8000-000000000004")!

    private func repository(_ transactions: [Transaction] = []) throws -> InMemoryLedgerRepository {
        let repository = InMemoryLedgerRepository(now: { F.now })
        let accounts = [
            Account(
                id: F.savingsID,
                name: "Everyday Savings",
                type: .savings,
                currencyCode: "INR",
                openingBalance: 10_000,
                sortOrder: 1,
            ),
            Account(id: Self.travelID, name: "Travel Wallet", type: .cash, currencyCode: "USD", sortOrder: 2),
            Account(id: Self.dollarID, name: "Dollar Card", type: .cash, currencyCode: "USD", sortOrder: 3),
            Account(id: Self.euroID, name: "Euro Card", type: .cash, currencyCode: "EUR", sortOrder: 4),
            Account(id: Self.cashID, name: "Cash", type: .cash, currencyCode: "INR", sortOrder: 5),
        ]
        for account in accounts {
            try repository.saveAccount(account)
        }
        try repository.seedDefaultCategories(names: CatalogDefaultCategoryNames())
        for transaction in transactions {
            try repository.saveTransaction(transaction)
        }
        return repository
    }

    private func useCases(_ repository: InMemoryLedgerRepository) -> TransactionUseCases {
        TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
    }

    private func form(_ repository: InMemoryLedgerRepository, mode: TransactionFormMode = .new(accountID: F.savingsID))
        -> TransactionFormViewModel
    {
        TransactionFormViewModel(
            useCases: useCases(repository),
            mode: mode,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
    }

    /// A new ₹10,000.00 transfer from Everyday Savings to Travel Wallet, with Received 120.00 typed.
    private func newTransfer(_ repository: InMemoryLedgerRepository) -> TransactionFormViewModel {
        let model = form(repository)
        model.type = .transfer
        model.expressionInput = "10000"
        model.transferAccountID = Self.travelID
        model.receivedText = "120.00"
        return model
    }

    /// The saved ₹10,000.00 transfer to Travel Wallet, received as $120.00.
    private var savedTransfer: Transaction {
        F.transfer(10_000, on: F.date(2026, 10, 19), to: Self.travelID, received: 120)
    }

    @Test("Check 1 (gate): To moved to Euro Card clears Received, Save is off and the hint asks for EUR")
    func currencyChangeClears() throws {
        let model = newTransfer(try repository())
        #expect(model.canSave)
        model.transferAccountID = Self.euroID
        #expect(model.receivedText.isEmpty)
        #expect(model.needsReceivedAmount)
        #expect(!model.canSave)
        #expect(model.receivedHint == "Enter the amount received in EUR.")
        #expect(model.save() == nil, "Nothing is saved with 120.00 read as EUR")
    }

    @Test("Check 2 (gate): after re-entering 110.00, Euro Card gets +€110.00 and Travel Wallet nothing")
    func savedInRightCurrency() throws {
        let repository = try repository()
        let model = newTransfer(repository)
        model.transferAccountID = Self.euroID
        model.receivedText = "110.00"
        #expect(model.receivedHint == nil)
        #expect(model.canSave)
        _ = try #require(model.save())
        let saved = try #require(try repository.transactions().first)
        #expect(saved.transferAccountID == Self.euroID)
        #expect(saved.amount == 10_000 && saved.destinationAmount == 110)
        #expect(try repository.balance(of: Self.euroID, today: F.today) == 110)
        #expect(try repository.balance(of: F.savingsID, today: F.today) == 0)
        #expect(try repository.balance(of: Self.travelID, today: F.today) == 0)
        #expect(try repository.transactions().count == 1)
    }

    @Test("Check 3: To moved to Dollar Card, also USD, keeps Received 120.00")
    func sameCurrencyKeeps() throws {
        let model = newTransfer(try repository())
        model.transferAccountID = Self.dollarID
        #expect(model.receivedText == "120.00")
        #expect(model.canSave)
    }

    @Test("Check 4 (gate): To moved to Cash, in From's currency, drops Received and saves none")
    func fromCurrencyDrops() throws {
        let repository = try repository()
        let model = newTransfer(repository)
        model.transferAccountID = Self.cashID
        #expect(!model.needsReceivedAmount, "The Received field goes away")
        #expect(model.receivedText.isEmpty)
        #expect(model.canSave)
        _ = try #require(model.save())
        let saved = try #require(try repository.transactions().first)
        #expect(saved.transferAccountID == Self.cashID && saved.destinationAmount == nil)
        #expect(try repository.balance(of: Self.cashID, today: F.today) == 10_000)
    }

    @Test("Check 4 (gate), edit: a saved $120.00 transfer moved to Cash saves no received amount")
    func editFromCurrencyDrops() throws {
        let original = savedTransfer
        let repository = try repository([original])
        let model = form(repository, mode: .edit(original.id))
        model.transferAccountID = Self.cashID
        #expect(model.receivedText.isEmpty)
        _ = try #require(model.save())
        let saved = try #require(try repository.transactions().first)
        #expect(saved.transferAccountID == Self.cashID && saved.destinationAmount == nil)
    }

    @Test("Check 5: To moved back to Travel Wallet after the clear leaves Received empty")
    func noSilentReturn() throws {
        let model = newTransfer(try repository())
        model.transferAccountID = Self.euroID
        model.transferAccountID = Self.travelID
        #expect(model.receivedText.isEmpty)
        #expect(!model.canSave)
        #expect(model.receivedHint == "Enter the amount received in USD.")
    }

    @Test("Opening a saved transfer keeps its $120.00: loading isn't a To change")
    func editOpensWithReceived() throws {
        let original = savedTransfer
        let model = form(try repository([original]), mode: .edit(original.id))
        #expect(model.receivedText == "120")
        #expect(model.isUnchanged)
        #expect(!model.hasUnsavedEdits)
    }

    @Test("Check 6 (gate): edit to €110.00, then one Undo restores $120.00 to Travel Wallet and Redo €110.00")
    func editUndoRedo() throws {
        let original = savedTransfer
        let repository = try repository([original])
        let model = form(repository, mode: .edit(original.id))
        model.transferAccountID = Self.euroID
        #expect(model.receivedText.isEmpty)
        #expect(!model.canSave)
        model.receivedText = "110.00"
        let change = try #require(model.save())
        let edited = try #require(try repository.transactions().first)
        #expect(edited.amount == 10_000 && edited.transferAccountID == Self.euroID && edited.destinationAmount == 110)

        let window = TestWindow(useCases(repository))
        window.history.record(change)
        window.history.undo()
        let restored = try #require(try repository.transactions().first)
        #expect(try repository.transactions().count == 1)
        #expect(restored.id == original.id && restored.amount == 10_000 && restored.accountID == F.savingsID)
        #expect(restored.transferAccountID == Self.travelID && restored.destinationAmount == 120)
        #expect(try repository.balance(of: Self.travelID, today: F.today) == 120)
        #expect(try repository.balance(of: Self.euroID, today: F.today) == 0)

        window.history.redo()
        let redone = try #require(try repository.transactions().first)
        #expect(redone.transferAccountID == Self.euroID && redone.destinationAmount == 110)
        #expect(try repository.balance(of: Self.euroID, today: F.today) == 110)
        #expect(try repository.balance(of: Self.travelID, today: F.today) == 0)
    }

    @Test("Check 7: an edit with To changed and Received cleared counts as unsaved (D385)")
    func clearingIsAnEdit() throws {
        let original = savedTransfer
        let model = form(try repository([original]), mode: .edit(original.id))
        model.transferAccountID = Self.euroID
        #expect(model.receivedText.isEmpty)
        #expect(model.hasUnsavedEdits)
        #expect(!model.isUnchanged)
    }

    @Test("The hint shows while Received is empty, hides once it reads, and shows again when emptied (UI Designer)")
    func hintVisibility() throws {
        let model = form(try repository())
        model.type = .transfer
        model.expressionInput = "10000"
        model.transferAccountID = Self.euroID
        #expect(model.receivedText.isEmpty)
        #expect(model.receivedHint == "Enter the amount received in EUR.", "A new transfer between currencies")
        #expect(!model.canSave)

        model.receivedText = "110.00"
        #expect(model.receivedHint == nil, "Hidden as soon as Received has a valid amount")
        #expect(model.canSave)

        model.receivedText = ""
        #expect(
            model.receivedHint == "Enter the amount received in EUR.",
            "Back when emptied, currencies still differ",
        )
        #expect(!model.canSave, "Save waits for Received (D446)")

        model.transferAccountID = Self.cashID
        #expect(model.receivedHint == nil, "Same currency as From: no Received, no hint")
        #expect(model.canSave)
    }
}
