import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// D453.1 (#189 I8): any import into a new account, from a file with no currency column, shows the new account's
/// currency picker, not only Debit & Credit files. It defaults to the device locale's currency (D387.3), and
/// the account is written only when the import is saved.
@Suite("CSV import new account currency (#189 I8, D453.1)")
@MainActor
struct CSVImportNewAccountCurrencyTests {
    typealias F = CSVFixture  // swiftlint:disable:this type_name

    /// No currency column; “Travel Card” is a new account, “Everyday Savings” an existing one.
    private static let maple = """
        Date,Details,Account,Amount
        2026-10-05,Metro Ticket,Travel Card,-12.50
        2026-10-06,Corner Coffee,Everyday Savings,-3.00
        """

    /// A Currency column reading EUR, into the new account “Harbor Card”.
    private static let harbor = """
        Date,Details,Account,Amount,Currency
        2026-11-03,Ferry Pass,Harbor Card,-12.50,EUR
        """

    private func match(_ text: String, file: String, in repository: InMemoryLedgerRepository) async
        -> CSVImportViewModel
    {
        let model = F.model(repository)
        await model.open(data: Data(text.utf8), fileName: file)
        await model.next()
        return model
    }

    @Test("D453 check 1: a generic file with no currency column offers the picker, INR first, and EUR shows −€12.50")
    func genericFile() async throws {
        let repository = try F.repository()
        let model = await match(Self.maple, file: "maple_oct.csv", in: repository)
        #expect(!model.isDebitAndCredit)
        #expect(model.step == .match)
        let travel = try #require(model.accountMatches.first { $0.name == "Travel Card" })
        #expect(travel.choice == .new)
        #expect(travel.newAccountCurrency == "INR")
        #expect(model.currencyOptions.first == "INR")
        #expect(model.accountMatches.first { $0.name == "Everyday Savings" }?.newAccountCurrency == nil)

        await model.setCurrency("EUR", forNewAccount: travel.id)
        #expect(model.accountMatches.first { $0.name == "Travel Card" }?.newAccountCurrency == "EUR")
        await model.next()
        #expect(model.step == .review)
        let metro = try #require(model.selectedRows.first { $0.title == "Metro Ticket" })
        #expect(metro.amount == "−€12.50")
        #expect(model.selectedRows.first { $0.title == "Corner Coffee" }?.amount.contains("₹") == true)

        await model.commit()
        #expect(model.step == .summary)
        let account = try F.account("Travel Card", in: repository)
        #expect(account.currencyCode == "EUR")
    }

    @Test("Left alone, the new account gets the device locale's currency")
    func defaultCurrency() async throws {
        let repository = try F.repository()
        let model = await match(Self.maple, file: "maple_oct.csv", in: repository)
        await model.next()
        await model.commit()
        #expect(try F.account("Travel Card", in: repository).currencyCode == "INR")
    }

    @Test("D453 check 2: with a Currency column, no picker shows and the account is the file's currency")
    func currencyColumn() async throws {
        let repository = try F.repository()
        let model = await match(Self.harbor, file: "harbor_nov.csv", in: repository)
        let harbor = try #require(model.accountMatches.first { $0.name == "Harbor Card" })
        #expect(harbor.choice == .new)
        #expect(harbor.newAccountCurrency == nil)
        await model.next()
        await model.commit()
        #expect(try F.account("Harbor Card", in: repository).currencyCode == "EUR")
    }

    @Test("D387.3: choosing a currency writes nothing; closing the import leaves no account behind")
    func cancelWritesNothing() async throws {
        let repository = try F.repository()
        let before = try repository.accounts()
        let model = await match(Self.maple, file: "maple_oct.csv", in: repository)
        let travel = try #require(model.accountMatches.first { $0.name == "Travel Card" })
        await model.setCurrency("EUR", forNewAccount: travel.id)
        await model.next()
        #expect(try repository.accounts() == before)
        model.close()
        #expect(try repository.accounts() == before)
        #expect(try repository.transactions().isEmpty)
    }

    @Test("D453.1: a changed currency re-checks transfer rows (D29): one into a EUR account needs its amount received")
    func transferRecheck() async throws {
        let model = await match(
            """
            Date,Type,Details,Account,To Account,Amount
            2026-10-07,Transfer,Top Up,Everyday Savings,Travel Card,1000.00
            """,
            file: "maple_transfer.csv",
            in: try F.repository(),
        )
        #expect(model.step == .match)
        let travel = try #require(model.accountMatches.first { $0.name == "Travel Card" })
        #expect(travel.newAccountCurrency == "INR")
        await model.next()
        #expect(model.failedCount == 0)
        model.back()
        await model.setCurrency("EUR", forNewAccount: travel.id)
        await model.next()
        #expect(model.failedCount == 1)
    }

    @Test("Matching the new name to an existing account takes the picker away")
    func matchedToExisting() async throws {
        let repository = try F.repository()
        let model = await match(Self.maple, file: "maple_oct.csv", in: repository)
        let travel = try #require(model.accountMatches.first { $0.name == "Travel Card" })
        let euros = try F.account("Travel Euros", in: repository)
        await model.setChoice(.existing(euros.id), for: travel.id)
        #expect(model.accountMatches.first { $0.name == "Travel Card" }?.newAccountCurrency == nil)
    }
}
