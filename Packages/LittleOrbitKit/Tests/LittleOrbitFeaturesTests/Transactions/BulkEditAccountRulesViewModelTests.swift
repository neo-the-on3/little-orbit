import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The bulk sheet when an Account change can't move every row (D223.3, D226.4, D227.2): nothing is saved, no
/// change comes back for Undo, and one message says why. The sample data is #34's own: Travel Card is USD.
@MainActor
@Suite("Bulk edit sheet: Account rules (#34)")
struct BulkEditAccountRulesViewModelTests {
    private static let zoneID = "Asia/Kolkata"
    private let now = Date(timeIntervalSince1970: 1_792_000_000)
    private let savings = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR", sortOrder: 1)
    private let groceryCash = Account(name: "Grocery Cash", type: .cash, currencyCode: "INR", sortOrder: 2)
    private let holidayFund = Account(name: "Holiday Fund", type: .savings, currencyCode: "INR", sortOrder: 3)
    private let travelCard = Account(name: "Travel Card", type: .creditCard, currencyCode: "USD", sortOrder: 4)

    private func row(_ type: TransactionType, _ amount: Decimal, in account: Account) -> Transaction {
        Transaction(
            type: type,
            amount: amount,
            date: now,
            timeZoneID: Self.zoneID,
            accountID: account.id,
            createdAt: now,
        )
    }

    private func repository(_ rows: [Transaction]) throws -> InMemoryLedgerRepository {
        let repository = InMemoryLedgerRepository(now: { [now] in now })
        for account in [savings, groceryCash, holidayFund, travelCard] {
            try repository.saveAccount(account)
        }
        for row in rows {
            try repository.saveTransaction(row)
        }
        return repository
    }

    private func moving(_ rows: [Transaction], to account: Account, in repository: InMemoryLedgerRepository)
        -> BulkEditViewModel
    {
        let model = BulkEditViewModel(
            useCases: TransactionUseCases(repository: repository),
            transactionIDs: rows.map(\.id),
            locale: Locale(identifier: "en_IN"),
            timeZone: TimeZone(identifier: Self.zoneID)!,
        )
        model.editsAccount = true
        model.accountID = account.id
        return model
    }

    @Test("D226.4: INR rows moved to a USD account save nothing and say why, singular and plural")
    func otherCurrency() throws {
        let rows = [
            row(.expense, 500, in: savings), row(.expense, 200, in: savings), row(.income, 900, in: savings),
        ]
        let repository = try repository(rows)
        let before = try repository.transactions()
        let several = moving(rows, to: travelCard, in: repository)
        #expect(several.apply() == nil, "No change, so no Undo step")
        #expect(
            several.errorMessage
                == "3 selected transactions are in INR, so they can’t move to Travel Card. Pick an account in INR to save."
        )
        let one = moving([rows[0]], to: travelCard, in: repository)
        #expect(one.apply() == nil)
        #expect(
            one.errorMessage
                == "A selected transaction is in INR, so it can’t move to Travel Card. Pick an account in INR to save."
        )
        #expect(try repository.transactions() == before, "Nothing is saved")
    }

    @Test("D227.2: a mixed selection names the account's currency and counts the rows not in it")
    func mixedCurrencies() throws {
        let rows = [row(.expense, 500, in: savings), row(.expense, 20, in: travelCard)]
        let repository = try repository(rows)
        let before = try repository.transactions()
        let model = moving(rows, to: groceryCash, in: repository)
        #expect(model.apply() == nil)
        #expect(
            model.errorMessage
                == "A selected transaction isn’t in INR, so it can’t move to Grocery Cash. Select transactions in one currency to change Account."
        )
        #expect(try repository.transactions() == before)
    }

    @Test("D223.3: a transfer moved to its own To account saves nothing and names the account")
    func ownToAccount() throws {
        var transfer = row(.transfer, 100, in: savings)
        transfer.transferAccountID = holidayFund.id
        let rows = [row(.expense, 500, in: savings), transfer]
        let repository = try repository(rows)
        let before = try repository.transactions()
        let model = moving(rows, to: holidayFund, in: repository)
        #expect(model.apply() == nil)
        #expect(
            model.errorMessage
                == "Holiday Fund is already the To account of a selected transfer. Pick a different account to save."
        )
        #expect(try repository.transactions() == before)
    }

    @Test("P24: the same rows move to an INR account with their amounts unchanged")
    func sameCurrencyMoves() throws {
        let rows = [row(.expense, 500, in: savings), row(.income, 900, in: savings)]
        let repository = try repository(rows)
        let model = moving(rows, to: groceryCash, in: repository)
        #expect(model.apply() != nil)
        let saved = try repository.transactions()
        #expect(saved.allSatisfy { $0.accountID == groceryCash.id })
        #expect(saved.map(\.amount).sorted() == [500, 900])
    }
}
