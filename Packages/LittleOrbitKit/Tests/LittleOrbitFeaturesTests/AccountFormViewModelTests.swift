import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

@MainActor
@Suite("Account form")
struct AccountFormViewModelTests {
    private func form(
        _ repository: InMemoryLedgerRepository,
        mode: AccountFormMode = .new,
        scheduled: Set<UUID> = [],
    ) -> AccountFormViewModel {
        AccountFormViewModel(
            useCases: FeatureFixture.useCases(repository),
            mode: mode,
            defaultCurrency: "INR",
            locale: FeatureFixture.india,
            scheduledAccountIDs: scheduled,
        )
    }

    @Test("First account: name, balance and currency, defaulting to the region's currency (S1, S25)")
    func firstAccount() throws {
        let repository = try FeatureFixture.repository([])
        let form = form(repository, mode: .firstAccount)
        #expect(form.title == "Your First Account")
        #expect(form.confirmTitle == "Add")
        #expect(form.currencyCode == "INR")
        #expect(!form.canSave)
        form.name = "Everyday Savings"
        form.amountText = "25,000"
        #expect(form.canSave)
        let saved = try #require(form.save())
        #expect(saved.openingBalance == 25_000)
        #expect(saved.currencyCode == "INR")
        #expect(saved.iconName == "dollarsign.circle" || saved.iconName == "building.columns")
        #expect(try repository.accounts().map(\.name) == ["Everyday Savings"])
    }

    @Test("A fresh form shows no name error; Save stays disabled (S26)")
    func freshFormHasNoNameError() throws {
        let form = form(try FeatureFixture.repository([]))
        #expect(!form.canSave)
        #expect(form.nameError == nil)
    }

    @Test("Empty or spaces-only names disable Save and show a message once edited (S26)")
    func nameValidation() throws {
        let form = form(try FeatureFixture.repository([]))
        form.name = "   "
        #expect(!form.canSave)
        #expect(form.nameError == "Enter a name for this account")
        #expect(form.save() == nil)
        #expect(form.nameError == "Enter a name for this account")
    }

    @Test("Whitespace-only names are invalid once edited, tabs and newlines included (D151)")
    func whitespaceNames() throws {
        for blank in [" ", "   ", "\t", "\n", " \t\n ", "\u{00A0}"] {
            let form = form(try FeatureFixture.repository([]))
            #expect(form.nameError == nil)
            form.name = blank
            #expect(!form.canSave, "\(blank.debugDescription) should not be saveable")
            #expect(form.nameError == "Enter a name for this account")
        }
    }

    @Test("Editing a name back to valid clears the error (D151)")
    func nameErrorClears() throws {
        let form = form(try FeatureFixture.repository([]))
        form.name = ""
        #expect(form.nameError == "Enter a name for this account")
        form.name = "Corner Wallet"
        #expect(form.nameError == nil)
        #expect(form.canSave)
    }

    @Test("Typing stops at 100 characters (S28)")
    func nameLimit() throws {
        let form = form(try FeatureFixture.repository([]))
        let hundred = "Holiday fund 🏖️" + String(repeating: "x", count: 86)
        form.name = hundred + "yz"
        #expect(form.name == hundred)
    }

    @Test("Bad amounts show an inline error and disable Save (S29, S8)")
    func amountValidation() throws {
        let form = form(try FeatureFixture.repository([]))
        form.name = "Everyday Savings"
        form.amountText = "1,25,000.0.0"
        #expect(form.amountError == "Enter an amount like 1,25,000.00.")
        #expect(!form.canSave)
        form.amountText = "-500"
        #expect(
            form.amountError
                == "Enter the amount without a minus sign. Use “Overdrawn / I owe this” for a negative balance."
        )
        form.amountText = "0.001"
        #expect(form.amountError == "INR amounts can have up to 2 decimal places.")
        form.amountText = "999,999,999.99"
        #expect(form.amountError == nil)
        #expect(form.canSave)
    }

    @Test("Sign toggle wording follows the type (S6)")
    func signToggle() throws {
        let form = form(try FeatureFixture.repository([]))
        for type in [AccountType.cash, .checking, .savings, .investment, .other] {
            form.type = type
            #expect(form.signToggleTitle == "Overdrawn / I owe this")
            #expect(!form.showsCreditLimit)
        }
        form.type = .creditCard
        #expect(form.signToggleTitle == "In credit / I’m owed")
        #expect(form.showsCreditLimit && form.showsAvailableCreditToggle)
        form.type = .loan
        #expect(form.signToggleTitle == "In credit / I’m owed")
        // Available credit never applies to loans (D104, S81), so the limit field is credit cards only.
        #expect(!form.showsCreditLimit && !form.showsAvailableCreditToggle)
    }

    @Test("A loan never saves a credit limit, even with text left from the card type (S81)")
    func loanIgnoresLimit() throws {
        let form = form(try FeatureFixture.repository([]))
        form.name = "Home Loan"
        form.type = .creditCard
        form.creditLimitText = "50000"
        form.type = .loan
        form.amountText = "800000"
        let saved = try #require(form.save())
        #expect(saved.creditLimit == nil)
    }

    @Test("Changing type swaps the default icon but keeps a picked one")
    func iconFollowsType() throws {
        let form = form(try FeatureFixture.repository([]))
        form.type = .creditCard
        #expect(form.iconSymbol == "creditcard")
        form.iconSymbol = "wallet.bifold"
        form.type = .cash
        #expect(form.iconSymbol == "wallet.bifold")
    }

    @Test("Overdrawn checking 2,000 saves −2,000; credit card 300 in credit saves +300 (S4, S5)")
    func signedSave() throws {
        let repository = try FeatureFixture.repository([])
        let checking = form(repository)
        checking.name = "Daily Checking"
        checking.type = .checking
        checking.amountText = "2,000"
        checking.flipsSign = true
        #expect(checking.save()?.openingBalance == -2_000)

        let card = form(repository)
        card.name = "Weekend Card"
        card.type = .creditCard
        card.amountText = "300"
        card.flipsSign = true
        #expect(card.save()?.openingBalance == 300)
    }

    @Test("Duplicate names are allowed with a soft hint (S27)")
    func duplicateHint() throws {
        let repository = try FeatureFixture.repository([Account(name: "Cash", type: .cash, currencyCode: "INR")])
        let form = form(repository)
        form.name = "Cash"
        #expect(form.duplicateHint == "Another account is already called “Cash”. You can keep both.")
        #expect(form.canSave)
        #expect(form.save() != nil)
        #expect(try repository.accounts().count == 2)
    }

    @Test("New accounts go to the end of the list")
    func sortOrder() throws {
        let repository = try FeatureFixture.repository()
        let form = form(repository)
        form.name = "Rainy Day Savings"
        let saved = try #require(form.save())
        #expect(saved.sortOrder == 8)
    }

    @Test("Edit loads the account, and turning the toggle off makes the balance positive (S9)")
    func edit() throws {
        let checking = Account(name: "Daily Checking", type: .checking, currencyCode: "INR", openingBalance: -2_000)
        let repository = try FeatureFixture.repository([checking])
        let form = form(repository, mode: .edit(checking.id))
        #expect(form.title == "Edit Account")
        #expect(form.name == "Daily Checking")
        #expect(form.amountText == "2,000.00")
        #expect(form.flipsSign)
        form.flipsSign = false
        #expect(form.save()?.openingBalance == 2_000)
        #expect(try repository.balance(of: checking.id) == 2_000)
    }

    @Test("Credit limit and Show available credit are saved for credit cards (D52)")
    func creditSettings() throws {
        let repository = try FeatureFixture.repository([])
        let form = form(repository)
        form.name = "Travel Card"
        form.type = .creditCard
        form.amountText = "30,000"
        form.creditLimitText = "1,00,000"
        form.showAvailableCredit = true
        let saved = try #require(form.save())
        #expect(saved.creditLimit == 100_000)
        #expect(saved.showAvailableCredit)
        #expect(saved.openingBalance == -30_000)
    }

    @Test("A zero credit limit is rejected")
    func zeroLimit() throws {
        let form = form(try FeatureFixture.repository([]))
        form.name = "Travel Card"
        form.type = .creditCard
        form.creditLimitText = "0"
        #expect(form.creditLimitError == "Enter a credit limit above 0, or leave it empty.")
        #expect(!form.canSave)
        form.creditLimitText = ""
        #expect(form.canSave)
    }

    @Test("Currency is editable without transactions and locked with one, either side of a transfer (S24, S82)")
    func currencyLock() throws {
        let pocket = Account(name: "Euro Pocket", type: .cash, currencyCode: "EUR", openingBalance: 300)
        let holiday = Account(name: "Holiday Fund", type: .savings, currencyCode: "USD", openingBalance: 1_240)
        let repository = try FeatureFixture.repository([pocket, holiday])
        let open = form(repository, mode: .edit(pocket.id))
        #expect(!open.isCurrencyLocked)
        open.currencyCode = "USD"
        #expect(open.save()?.currencyCode == "USD")

        try repository.saveTransaction(
            Transaction(type: .transfer, amount: 10, accountID: holiday.id, transferAccountID: pocket.id)
        )
        let locked = form(repository, mode: .edit(pocket.id))
        #expect(locked.isCurrencyLocked)
        #expect(
            locked.currencyLockMessage
                == "Currency can't be changed once the account has transactions or scheduled items."
        )
    }

    @Test("A scheduled item alone locks the currency (S83)")
    func scheduledLocks() throws {
        let pocket = Account(name: "Euro Pocket", type: .cash, currencyCode: "EUR")
        let repository = try FeatureFixture.repository([pocket])
        #expect(form(repository, mode: .edit(pocket.id), scheduled: [pocket.id]).isCurrencyLocked)
    }

    @Test("Visibility toggles map to hidden and excluded")
    func visibility() throws {
        let form = form(try FeatureFixture.repository([]))
        form.name = "Old Locker"
        form.isHidden = true
        form.excludeFromNetWealth = true
        let saved = try #require(form.save())
        #expect(saved.isHidden)
        #expect(!saved.includeInNetWorth)
    }

    @Test("Currency options read like INR — Indian Rupee")
    func currencyTitles() throws {
        let form = form(try FeatureFixture.repository([]))
        #expect(form.currencyTitle(for: "INR") == "INR — Indian Rupee")
        #expect(form.currencyOptions.contains("KWD"))
    }

    @Test("The currency picker lists circulating currencies only, no fund or test codes")
    func currencyPickerCodes() throws {
        let form = form(try FeatureFixture.repository([]))
        for code in ["USN", "UYI", "UYW", "BOV", "CHE", "CHW", "CLF", "COU", "MXV", "XTS", "XXX", "XAU", "XDR"] {
            #expect(!form.currencyOptions.contains(code), "\(code) should not be offered")
        }
        for code in ["INR", "USD", "EUR", "CHF", "XAF", "XOF", "XPF", "XCD"] {
            #expect(form.currencyOptions.contains(code))
        }
    }

    // MARK: - Edit fails closed (Tech Architect's review of #82)

    @Test("Editing an account that doesn't exist shows an error and never creates one")
    func editUnknownAccount() throws {
        let repository = try FeatureFixture.repository()
        let before = try repository.accounts()
        let form = form(repository, mode: .edit(UUID()))
        #expect(form.loadError == AccountFormViewModel.missingAccountMessage)
        form.name = "Brand New"
        form.amountText = "100"
        #expect(!form.canSave)
        #expect(form.save() == nil)
        #expect(try repository.accounts() == before)
    }

    @Test("An account deleted while its edit form is open isn't saved back")
    func editDeletedMidEdit() throws {
        let repository = try FeatureFixture.repository()
        let wallet = try #require(try repository.accounts().first { $0.name == "Corner Wallet" })
        let form = form(repository, mode: .edit(wallet.id))
        #expect(form.loadError == nil)
        try repository.deleteAccount(id: wallet.id)
        form.name = "Renamed Wallet"
        #expect(form.save() == nil)
        #expect(form.loadError == AccountFormViewModel.missingAccountMessage)
        #expect(!form.canSave)
        #expect(try repository.accounts().contains { $0.id == wallet.id } == false)
        #expect(try repository.accounts().contains { $0.name == "Renamed Wallet" } == false)
    }

    @Test("A read error on an edit form is shown, and Save never creates a new account")
    func editReadError() throws {
        let fake = FakeAccountUseCases()
        fake.formContextError = FakeAccountUseCases.Failure()
        let form = AccountFormViewModel(
            loadAccountForm: fake,
            saveAccount: fake,
            mode: .edit(UUID()),
            defaultCurrency: "INR",
            locale: FeatureFixture.india,
        )
        #expect(form.loadError == AccountFormViewModel.loadFailedMessage)
        form.name = "Corner Wallet"
        form.amountText = "1"
        #expect(!form.canSave)
        #expect(form.save() == nil)
        #expect(fake.savedDrafts.isEmpty)
    }

    @Test("A new-account form passes the draft to the save use case with no account id")
    func newFormUsesSaveUseCase() throws {
        let fake = FakeAccountUseCases()
        let form = AccountFormViewModel(
            loadAccountForm: fake,
            saveAccount: fake,
            mode: .new,
            defaultCurrency: "INR",
            locale: FeatureFixture.india,
        )
        form.name = "Spare Cash"
        form.amountText = "1,25,000.00"
        #expect(form.save() != nil)
        let saved = try #require(fake.savedDrafts.first)
        #expect(saved.accountID == nil)
        #expect(saved.draft.enteredAmount == 125_000)
    }

    @Test("The save use case reporting the account gone shows the missing-account error")
    func saveReportsMissingAccount() throws {
        let fake = FakeAccountUseCases()
        let account = Account(name: "Corner Wallet", type: .cash, currencyCode: "INR")
        fake.formContext = AccountFormContext(accounts: [account], account: account)
        fake.saveError = AccountUseCaseError.accountNotFound
        let form = AccountFormViewModel(
            loadAccountForm: fake,
            saveAccount: fake,
            mode: .edit(account.id),
            defaultCurrency: "INR",
            locale: FeatureFixture.india,
        )
        #expect(form.loadError == nil)
        #expect(form.save() == nil)
        #expect(form.loadError == AccountFormViewModel.missingAccountMessage)
        #expect(!form.canSave)
    }

    @Test("Loading an account into the edit form doesn't count as editing the name")
    func editDoesNotMarkNameEdited() throws {
        let repository = try FeatureFixture.repository()
        let wallet = try #require(try repository.accounts().first { $0.name == "Corner Wallet" })
        let form = form(repository, mode: .edit(wallet.id))
        #expect(form.name == "Corner Wallet")
        #expect(!form.hasEditedName)
        form.name = "Wallet"
        #expect(form.hasEditedName)
    }
}
