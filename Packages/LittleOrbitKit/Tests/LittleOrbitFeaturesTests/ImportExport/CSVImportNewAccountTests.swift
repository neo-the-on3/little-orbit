import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

@Suite("I7 deferred New Account")
@MainActor
struct CSVImportNewAccountTests {
    @Test("Travel Card is selected, remains unsaved, imports with EUR, and in-session Undo removes it")
    func travelCard() async throws {
        let repository = try CSVFixture.repository()
        let model = CSVFixture.model(repository)
        await model.open(
            data: Data("Date,Details,Amount\n2026-10-05,Metro Ticket,-12.50\n".utf8),
            fileName: "maple_oct.csv",
        )
        await model.next()
        let form = model.newAccountForm()
        #expect(form.currencyCode == "INR")
        #expect(!form.canSave)
        form.name = "Travel Card"
        form.currencyCode = "EUR"
        form.type = .creditCard
        form.creditLimitText = "500"
        form.amountText = "20"
        let account = try #require(form.save())
        model.selectNewAccount(account)
        #expect(model.step == .account)
        #expect(model.targetAccountID == account.id)
        #expect(model.accountOptions.last?.name == "Travel Card")
        #expect(try repository.accounts().count == 3)
        await model.next()
        if model.step == .match { await model.next() }
        #expect(model.readyCount == 1)
        #expect(model.selectedRows.first?.amount.contains("€") == true)
        await model.commit()
        let saved = try CSVFixture.account("Travel Card", in: repository)
        #expect(saved.currencyCode == "EUR")
        #expect(saved.type == .creditCard)
        #expect(saved.creditLimit == 500)
        #expect(saved.openingBalance == -20)
        #expect(model.undoMessage.contains("the new account “Travel Card”"))
        model.undo()
        #expect(model.isUndone)
        #expect(try repository.accounts().count == 3)
        #expect(try repository.transactions().isEmpty)
    }

    @Test("Cancelling either the account sheet or the import writes nothing")
    func cancel() async throws {
        let repository = try CSVFixture.repository()
        let model = CSVFixture.model(repository)
        await model.open(data: Data("Date,Amount\n2026-10-05,-12.50\n".utf8), fileName: "maple_oct.csv")
        await model.next()
        let dismissedForm = model.newAccountForm()
        dismissedForm.name = "Discarded"
        #expect(model.targetAccountID == nil)
        let form = model.newAccountForm()
        form.name = "Travel Card"
        model.selectNewAccount(try #require(form.save()))
        model.close()
        #expect(try repository.accounts().count == 3)
        #expect(try repository.transactions().isEmpty)
    }

    @Test("A ledger refresh retains the pending selection; selecting an existing account creates no extra account")
    func switchAccount() async throws {
        let repository = try CSVFixture.repository()
        let model = CSVFixture.model(repository)
        await model.open(data: Data("Date,Amount\n2026-10-05,-12.50\n".utf8), fileName: "maple_oct.csv")
        await model.next()
        let form = model.newAccountForm()
        form.name = "Travel Card"
        let account = try #require(form.save())
        model.selectNewAccount(account)
        try repository.saveAccount(Account(name: "Other", currencyCode: "INR"))
        await model.dataChanged()
        #expect(model.targetAccountID == account.id)
        model.targetAccountID = try CSVFixture.account("Everyday Savings", in: repository).id
        await model.next()
        if model.step == .match { await model.next() }
        await model.commit()
        #expect(model.step == .summary)
        #expect(try repository.accounts().count == 4)
        #expect(try repository.accounts().allSatisfy { $0.name != "Travel Card" })
    }
    @Test("New-account currency follows the locale, then the picker; a mapped Currency column wins")
    func currencyRules() async throws {
        let repository = try CSVFixture.repository()
        for hasCurrency in [false, true] {
            let model = CSVImportViewModel(
                useCases: ImportUseCases(repository: repository),
                defaultCurrency: "USD",
                locale: CSVFixture.india,
                timeZone: CSVFixture.zone,
            )
            let text =
                hasCurrency
                ? "Date,Amount,Currency\n2026-10-05,-12.50,EUR\n"
                : "Date,Amount\n2026-10-05,-12.50\n"
            await model.open(data: Data(text.utf8), fileName: "maple_oct.csv")
            await model.next()
            let form = model.newAccountForm()
            #expect(form.currencyCode == "INR")
            form.name = "Travel Card"
            model.selectNewAccount(try #require(form.save()))
            await model.next()
            let match = try #require(model.accountMatches.first)
            if hasCurrency {
                #expect(match.newAccountCurrency == nil)
                #expect(model.newAccountCurrencyFootnote == nil)
            } else {
                #expect(match.newAccountCurrency == "INR")
                #expect(model.newAccountCurrencyFootnote != nil)
                await model.setCurrency("EUR", forNewAccount: match.id)
                #expect(model.accountMatches.first?.newAccountCurrency == "EUR")
            }
            await model.next()
            #expect(model.selectedRows.first?.amount.contains("€") == true)
            #expect(model.selectedRows.first?.detail.contains("Travel Card") == true)
        }
    }
    @Test("A deferred target takes the first file currency and rejects a later mismatch")
    func mixedFileCurrencies() async throws {
        let repository = try CSVFixture.repository()
        let model = CSVFixture.model(repository)
        await model.open(
            data: Data("Date,Amount,Currency\n2026-10-05,-12.50,EUR\n2026-10-06,-3,USD\n".utf8),
            fileName: "harbor_nov.csv",
        )
        await model.next()
        let form = model.newAccountForm()
        form.name = "Travel Card"
        model.selectNewAccount(try #require(form.save()))
        await model.next()
        #expect(model.accountMatches.first?.choice == .new)
        #expect(model.preview?.matches.first?.currencyCode == "EUR")
        #expect(model.readyCount == 1)
        #expect(model.failedCount == 1)
    }
    @Test("Mapping a Currency column after using the new-account picker makes the file currency win")
    func mappedCurrencyReplacesPicker() async throws {
        let repository = try CSVFixture.repository()
        let model = CSVFixture.model(repository)
        await model.open(
            data: Data("Date,Amount,Foreign code\n2026-10-05,-12.50,EUR\n".utf8),
            fileName: "maple_oct.csv",
        )
        await model.next()
        let form = model.newAccountForm()
        form.name = "Travel Card"
        model.selectNewAccount(try #require(form.save()))
        await model.next()
        let match = try #require(model.accountMatches.first)
        await model.setCurrency("USD", forNewAccount: match.id)
        model.back()
        model.back()
        model.setField(.currency, forColumn: 2)
        await model.next()
        await model.next()
        #expect(model.accountMatches.first?.newAccountCurrency == nil)
        #expect(model.newAccountCurrencyFootnote == nil)
        await model.next()
        #expect(model.failedCount == 0)
        #expect(model.selectedRows.first?.amount.contains("€") == true)
    }
}
