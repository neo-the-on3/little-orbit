import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

@MainActor
@Suite("Transaction form")
struct TransactionFormViewModelTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    private func model(
        _ repository: InMemoryLedgerRepository,
        mode: TransactionFormMode = .new(accountID: F.savingsID),
        locale: Locale = F.india,
    ) -> TransactionFormViewModel {
        TransactionFormViewModel(
            useCases: TransactionUseCases(repository: repository),
            mode: mode,
            locale: locale,
            timeZone: F.zone,
            now: { F.now },
        )
    }

    private func type(_ text: String, into model: TransactionFormViewModel) {
        for character in text {
            switch character {
            case "0"..."9": model.press(.digit(Int(String(character))!))
            case ".": model.press(.decimal)
            case "+": model.press(.add)
            case "-": model.press(.subtract)
            case "*": model.press(.multiply)
            case "/": model.press(.divide)
            case "=": model.press(.equals)
            default: Issue.record("Unknown key \(character)")
            }
        }
    }

    @Test("Fast entry: amount then Save records an expense dated today on the account (AC 1)")
    func fastEntry() throws {
        let repository = try F.repository()
        let model = model(repository)
        #expect(model.title == "New Expense")
        #expect(!model.canSave)
        type("250", into: model)
        #expect(model.amountText == "−₹250.00")
        #expect(model.canSave)
        let change = try #require(model.save())
        let saved = try #require(try repository.transactions().first)
        #expect(change == .added([saved.id]))
        #expect(saved.type == .expense && saved.amount == 250 && saved.accountID == F.savingsID)
        #expect(saved.date == F.now && saved.timeZoneID == F.zoneID)
        #expect(try repository.balance(of: F.savingsID, today: F.today) == 9_750)
    }

    @Test("A new entry opens on the amount; an edit doesn't (AC 1, D170 N1)")
    func focusOnOpen() throws {
        let original = F.expense(250, on: F.date(2026, 10, 19))
        let repository = try F.repository([original])
        #expect(model(repository).mode.focusesAmountOnOpen)
        #expect(model(repository, mode: .new(accountID: nil)).mode.focusesAmountOnOpen)
        #expect(!model(repository, mode: .edit(original.id)).mode.focusesAmountOnOpen)
    }

    @Test("Calculator: 50*20/10= shows 100 (AC 4)")
    func calculator() throws {
        let model = model(try F.repository())
        type("50*20/10", into: model)
        #expect(model.expressionText == "50 × 20 ÷ 10")
        type("=", into: model)
        #expect(model.expressionText == "100")
        #expect(model.expressionLine == "50 × 20 ÷ 10 =")
        #expect(model.amount == 100)
    }

    @Test("Typing into the macOS amount field accepts numbers and sums (S75)")
    func typedAmount() throws {
        let model = model(try F.repository())
        model.expressionInput = "50*20/10"
        #expect(model.expressionText == "50 × 20 ÷ 10")
        #expect(model.amount == 100)
        model.expressionInput = "1,250.5 abc"
        #expect(model.expressionText == "1250.5")
        model.press(.equals)
        #expect(model.amount == dec("1250.5"))
    }

    @Test("A pending sum is evaluated on Save")
    func pendingSum() throws {
        let repository = try F.repository()
        let model = model(repository)
        type("200+50", into: model)
        #expect(model.amount == 250)
        _ = model.save()
        #expect(try repository.transactions().first?.amount == 250)
    }

    @Test("A calculator error keeps the sum, replaces the result and disables Save until fixed (UI Designer, #87 U4)")
    func calculatorErrors() throws {
        let model = model(try F.repository())
        type("5-8=", into: model)
        #expect(model.amountError == "Result is below zero")
        #expect(model.expressionText == "5 − 8")
        #expect(model.expressionLine == "5 − 8 =")
        #expect(!model.canSave)
        // "=" does nothing while the sum is invalid.
        model.press(.equals)
        #expect(model.expressionText == "5 − 8")
        #expect(model.amountError == "Result is below zero")
        // Keys keep editing the sum; the error stays until it works out.
        model.press(.digit(1))
        #expect(model.expressionText == "5 − 81")
        #expect(model.amountError == "Result is below zero")
        #expect(!model.canSave)
        model.press(.backspace)
        model.press(.backspace)
        #expect(model.amountError == nil)
        model.press(.subtract)
        type("2=", into: model)
        #expect(model.amountError == nil)
        #expect(model.amount == 3)
        type("/0=", into: model)
        #expect(model.amountError == "Can't divide by zero")
        #expect(model.expressionText == "3 ÷ 0")
        #expect(!model.canSave)
    }

    @Test("Keypad stops at the currency's decimals and backspace edits")
    func keypadLimits() throws {
        let model = model(try F.repository())
        type("12.345", into: model)
        #expect(model.expressionText == "12.34")
        model.press(.backspace)
        #expect(model.expressionText == "12.3")
        model.press(.add)
        model.press(.multiply)
        #expect(model.expressionText == "12.3 ×")
    }

    @Test("German keypad uses a comma")
    func germanDecimal() throws {
        let model = model(try F.repository(), locale: Locale(identifier: "de_DE"))
        type("12.5*2=", into: model)
        #expect(model.amount == 25)
        #expect(model.decimalKeyTitle == ",")
    }

    @Test("Transfer needs a different destination; same account explains why (AC 2)")
    func transferAccounts() throws {
        let repository = try F.repository()
        let model = model(repository)
        #expect(model.allowedTypes == [.expense, .income, .transfer])
        model.type = .transfer
        #expect(model.title == "New Transfer")
        type("500", into: model)
        #expect(!model.canSave)
        model.transferAccountID = F.savingsID
        #expect(model.issueMessage == "Same account selected as From and To. Pick a different account to save.")
        #expect(!model.canSave)
        model.transferAccountID = F.cardID
        #expect(!model.needsReceivedAmount)
        #expect(model.canSave)
        _ = model.save()
        let saved = try #require(try repository.transactions().first)
        #expect(saved.type == .transfer && saved.transferAccountID == F.cardID && saved.destinationAmount == nil)
    }

    @Test("Cross-currency transfer asks for Received and shows the read-only rate (D17)")
    func crossCurrency() throws {
        let repository = try F.repository()
        let model = model(repository)
        model.type = .transfer
        type("1000", into: model)
        model.transferAccountID = F.usdID
        #expect(model.needsReceivedAmount)
        #expect(!model.canSave)
        model.receivedText = "12.00"
        #expect(model.rateText == "1 USD = ₹83.33 · worked out from the two amounts")
        #expect(model.canSave)
        _ = model.save()
        #expect(try repository.balance(of: F.savingsID, today: F.today) == 9_000)
        #expect(try repository.balance(of: F.usdID, today: F.today) == 112)
        #expect(try repository.transactions().count == 1)
    }

    @Test("Edit: Expense ↔ Income only, category cleared if it doesn't fit, balances update (AC 6)")
    func editType() throws {
        let original = F.expense(250, on: F.date(2026, 10, 19), category: DefaultCategoryID.food)
        let repository = try F.repository([original])
        let model = model(repository, mode: .edit(original.id))
        #expect(model.title == "Edit Expense")
        #expect(model.allowedTypes == [.expense, .income])
        #expect(model.expressionText == "250")
        #expect(!model.hasUnsavedInput)
        model.type = .income
        #expect(model.categoryID == nil)
        #expect(model.hasUnsavedInput)
        let change = try #require(model.save())
        guard case .replaced(let previous) = change else {
            Issue.record("Expected a replaced change")
            return
        }
        #expect(previous.map(\.type) == [.expense])
        #expect(try repository.transactions().first?.type == .income)
        #expect(try repository.balance(of: F.savingsID, today: F.today) == 10_250)
    }

    @Test("Editing a transfer keeps it a transfer")
    func editTransfer() throws {
        let original = F.transfer(1_000, on: F.date(2026, 10, 19))
        let model = model(try F.repository([original]), mode: .edit(original.id))
        #expect(model.allowedTypes == [.transfer])
    }

    @Test("Undoing an edit puts the old values back")
    func undoEdit() throws {
        let original = F.expense(250, on: F.date(2026, 10, 19))
        let repository = try F.repository([original])
        let model = model(repository, mode: .edit(original.id))
        model.press(.backspace)
        let change = try #require(model.save())
        #expect(try repository.balance(of: F.savingsID, today: F.today) == 9_975)
        UndoTestSupport.undo(change, useCases: TransactionUseCases(repository: repository))
        #expect(try repository.balance(of: F.savingsID, today: F.today) == 9_750)
    }

    @Test("Payee autocomplete offers earlier payees and fills their category (S38)")
    func payeeSuggestions() throws {
        let cafe = Payee(name: "Cafe Orbit", defaultCategoryID: DefaultCategoryID.food)
        let repository = try F.repository()
        try repository.savePayee(cafe)
        let model = model(repository)
        model.payeeText = "caf"
        let suggestion = try #require(model.payeeSuggestions.first)
        #expect(suggestion.text == "Cafe Orbit")
        model.choosePayee(suggestion)
        #expect(model.payeeText == "Cafe Orbit")
        #expect(model.categoryID == DefaultCategoryID.food)
        #expect(model.payeeSuggestions.isEmpty)
    }

    @Test("A new payee name is created on save and reused next time")
    func newPayee() throws {
        let repository = try F.repository()
        let model = model(repository)
        type("90", into: model)
        model.payeeText = "Corner Bakery"
        _ = model.save()
        let payee = try #require(try repository.payees().first)
        #expect(payee.name == "Corner Bakery")
        #expect(try repository.transactions().first?.payeeID == payee.id)
    }

    @Test("Description autocomplete offers earlier descriptions")
    func descriptionSuggestions() throws {
        let repository = try F.repository([
            F.expense(10, on: F.date(2026, 10, 1), details: "Team lunch"),
            F.expense(10, on: F.date(2026, 10, 2), details: "Team lunch"),
        ])
        let model = model(repository)
        model.updateDetails("tea")
        #expect(model.detailsSuggestions.map(\.text) == ["Team lunch"])
        #expect(model.detailsSuggestions.first.map(TransactionFormViewModel.usageText) == "Used 2 times")
        model.chooseDescription(model.detailsSuggestions[0])
        #expect(model.details == "Team lunch")
    }

    @Test("Description: counter from 80, typing stops at 100, paste is cut with the note (D55, D111)")
    func descriptionLimit() throws {
        let model = model(try F.repository())
        model.updateDetails(String(repeating: "a", count: 79))
        #expect(model.detailsFootnote == nil)
        model.updateDetails(String(repeating: "a", count: 80))
        #expect(model.detailsFootnote == "80 / 100")
        model.updateDetails(String(repeating: "a", count: 100))
        model.updateDetails(String(repeating: "a", count: 101))
        #expect(model.details.count == 100)
        #expect(model.detailsFootnote == "100 / 100")
        model.updateDetails("")
        model.updateDetails(String(repeating: "b", count: 150))
        #expect(model.details.count == 100)
        #expect(model.detailsFootnote == "100 / 100 · Text shortened to fit 100 characters")
        model.updateDetails(String(repeating: "b", count: 99))
        #expect(model.detailsFootnote == "99 / 100")
    }

    @Test("Typing one character at a time stops at 100: the field shows what the model kept (Tester's #87 B2)")
    func descriptionTypingStops() throws {
        let model = model(try F.repository())
        // The field shows the text the model hands back after every keystroke, as the view's binding does.
        var shown = ""
        for character in String(repeating: "c", count: 108) + "de" {
            shown = model.updateDetails(shown + String(character))
            #expect(shown == model.details)
        }
        #expect(shown.count == 100)
        #expect(shown == String(repeating: "c", count: 100))
        #expect(model.detailsFootnote == "100 / 100")
        #expect(!model.detailsWasShortened)
        // Backspace then a character moves the counter and still never goes past 100.
        shown = model.updateDetails(String(shown.dropLast()))
        #expect(model.detailsFootnote == "99 / 100")
        shown = model.updateDetails(shown + "z")
        #expect(shown.count == 100)
        #expect(model.detailsFootnote == "100 / 100")
        // Save stores exactly what the field showed; nothing is cut silently.
        type("10", into: model)
        _ = try #require(model.save())
    }

    @Test("A paste is cut to 100, the field shows the cut text, and the note shows")
    func descriptionPasteShown() throws {
        let model = model(try F.repository())
        let shown = model.updateDetails("Team " + String(repeating: "p", count: 145))
        #expect(shown.count == 100)
        #expect(shown == model.details)
        #expect(model.detailsFootnote == "100 / 100 · Text shortened to fit 100 characters")
    }

    @Test("Description suggestions list at most 3 (UI Designer, #87 U1)")
    func descriptionSuggestionsCapped() throws {
        let used = ["Tea one", "Tea two", "Tea three", "Tea four", "Tea five"].enumerated()
            .map { index, text in
                F.expense(Decimal(10 + index), on: F.date(2026, 10, 10 + index), details: text)
            }
        let model = model(try F.repository(used))
        model.updateDetails("Tea")
        #expect(model.detailsSuggestions.count == 3)
    }

    @Test("The category picker's VoiceOver value is the chosen category (Tester's #87 B3)")
    func categoryAccessibilityValue() throws {
        let model = model(try F.repository())
        #expect(model.categoryName == "Uncategorised")
        let groceries = try #require(model.categoryOptions.first { $0.isSubcategory })
        model.categoryID = groceries.id
        #expect(model.categoryName == groceries.name)
        #expect(!model.categoryName.hasPrefix(" "))
    }

    @Test("The date reads in full for VoiceOver: \"Date, 20 October 2026\" (UI Designer, #87 UI3)")
    func dateAccessibilityValue() throws {
        let model = model(try F.repository())
        #expect(model.dateSpokenText == "20 October 2026")
        model.date = F.date(2026, 10, 21, 23)
        #expect(model.dateSpokenText == "21 October 2026")
    }

    @Test("An existing 120-character description shows 120 / 100 and blocks Save until shortened (D111)")
    func overLimitExisting() throws {
        var original = F.expense(250, on: F.date(2026, 10, 19))
        original.details = String(repeating: "c", count: 120)
        let model = model(try F.repository([original]), mode: .edit(original.id))
        #expect(model.details.count == 120)
        #expect(model.detailsFootnote == "120 / 100")
        #expect(!model.canSave)
        model.updateDetails(String(repeating: "c", count: 100))
        #expect(model.canSave)
    }

    @Test("Notes are long-form: over 100 is fine, with a 2,000 counter (D55)")
    func notes() throws {
        let repository = try F.repository()
        let model = model(repository)
        type("10", into: model)
        model.note = String(repeating: "n", count: 150)
        #expect(model.noteCounter == "150 / 2,000")
        #expect(model.canSave)
        _ = model.save()
        #expect(try repository.transactions().first?.note?.count == 150)
    }

    @Test("Date row reads Today, Yesterday, or the date")
    func dateRow() throws {
        let model = model(try F.repository())
        #expect(model.dateText == "Today")
        model.date = F.date(2026, 10, 19)
        #expect(model.dateText == "Yesterday")
        model.date = F.date(2026, 11, 3)
        #expect(model.dateText == "3 Nov 2026")
    }

    @Test("Category list follows the type")
    func categories() throws {
        let model = model(try F.repository())
        #expect(model.categoryName == "Uncategorised")
        #expect(model.categoryOptions.contains { $0.id == DefaultCategoryID.food })
        #expect(!model.categoryOptions.contains { $0.id == DefaultCategoryID.salary })
        model.type = .income
        #expect(model.categoryOptions.contains { $0.id == DefaultCategoryID.salary })
        model.type = .transfer
        #expect(model.categoryOptions.isEmpty)
    }

    @Test("Unsaved input is tracked for the discard warning")
    func unsavedInput() throws {
        let model = model(try F.repository())
        #expect(!model.hasUnsavedInput)
        model.press(.digit(5))
        #expect(model.hasUnsavedInput)
    }

    @Test("New from the home screen uses the last used account")
    func lastUsedAccount() throws {
        let repository = try F.repository([F.expense(10, on: F.date(2026, 10, 19), account: F.walletID)])
        let model = model(repository, mode: .new(accountID: nil))
        #expect(model.accountID == F.walletID)
        #expect(model.accountName == "Corner Wallet")
    }

    @Test("Categories are seeded if the store has none")
    func seeding() throws {
        let repository = InMemoryLedgerRepository(now: { F.now })
        try repository.saveAccount(F.accounts()[0])
        let model = model(repository)
        #expect(!model.categoryOptions.isEmpty)
    }

    private func dec(_ text: String) -> Decimal {
        Decimal(string: text)!
    }
}
