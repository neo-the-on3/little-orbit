import Foundation
import LittleOrbitDomain
import Testing

@Suite("Account draft")
struct AccountDraftTests {
    @Test("Checking 2,000 marked overdrawn saves −2,000 (S4)")
    func overdrawnAsset() {
        let draft = AccountDraft(
            name: "Daily Checking",
            type: .checking,
            currencyCode: "INR",
            enteredAmount: 2_000,
            flipsSign: true,
        )
        #expect(draft.applied(to: Account()).openingBalance == -2_000)
    }

    @Test("Credit card 300 marked in credit saves +300 (S5)")
    func inCreditCard() {
        let draft = AccountDraft(
            name: "Weekend Card",
            type: .creditCard,
            currencyCode: "INR",
            enteredAmount: 300,
            flipsSign: true,
        )
        #expect(draft.applied(to: Account()).openingBalance == 300)
    }

    @Test("Credit card or loan 500 with the toggle off saves −500 (S7)", arguments: [AccountType.creditCard, .loan])
    func liabilityDefault(type: AccountType) {
        let draft = AccountDraft(name: "Owed", type: type, currencyCode: "INR", enteredAmount: 500)
        #expect(draft.applied(to: Account()).openingBalance == -500)
    }

    @Test("Editing splits the stored balance back into amount and toggle (S9)")
    func editingRoundTrip() {
        let overdrawn = Account(name: "Daily Checking", type: .checking, currencyCode: "INR", openingBalance: -2_000)
        var draft = AccountDraft(editing: overdrawn)
        #expect(draft.enteredAmount == 2_000)
        #expect(draft.flipsSign)
        draft.flipsSign = false
        #expect(draft.applied(to: overdrawn).openingBalance == 2_000)

        let owing = Account(name: "Travel Card", type: .creditCard, currencyCode: "INR", openingBalance: -30_000)
        #expect(!AccountDraft(editing: owing).flipsSign)
        let credit = Account(name: "Weekend Card", type: .creditCard, currencyCode: "INR", openingBalance: 2_000)
        #expect(AccountDraft(editing: credit).flipsSign)
    }

    @Test("Empty or spaces-only names are missing (S26)", arguments: ["", "   ", "\n"])
    func missingName(name: String) {
        #expect(AccountDraft(name: name).nameIssue == .missing)
    }

    @Test("100 characters with emoji are fine; 101 is too long (S28)")
    func nameLength() {
        let hundred = "Holiday fund 🏖️" + String(repeating: "x", count: 86)
        #expect(hundred.count == 100)
        #expect(AccountDraft(name: hundred).nameIssue == nil)
        #expect(AccountDraft(name: hundred + "y").nameIssue == .tooLong)
        #expect(AccountDraft.clampedName(hundred + "y") == hundred)
    }

    @Test("Duplicate names are allowed but reported for the soft hint (S27)")
    func duplicateHint() {
        let cash = Account(name: "Cash", type: .cash, currencyCode: "INR")
        let draft = AccountDraft(name: " cash ", type: .cash, currencyCode: "INR")
        #expect(draft.duplicateName(among: [cash]) == "Cash")
        #expect(draft.duplicateName(among: [cash], editing: cash.id) == nil)
        #expect(AccountDraft(name: "Wallet").duplicateName(among: [cash]) == nil)
    }

    @Test("Credit settings are kept only for credit cards (D104, S81)")
    func creditSettings() {
        var draft = AccountDraft(name: "Travel Card", type: .creditCard, currencyCode: "INR", enteredAmount: 30_000)
        draft.creditLimit = 100_000
        draft.showAvailableCredit = true
        let card = draft.applied(to: Account())
        #expect(card.creditLimit == 100_000)
        #expect(card.showAvailableCredit)

        draft.type = .loan
        let loan = draft.applied(to: Account())
        #expect(loan.creditLimit == nil, "A credit limit is for credit cards only (S81)")
        #expect(!loan.showAvailableCredit)

        draft.type = .savings
        let savings = draft.applied(to: Account())
        #expect(savings.creditLimit == nil)
        #expect(!savings.showAvailableCredit)
    }

    @Test("Visibility maps to isHidden and includeInNetWorth, and fields are copied")
    func visibilityAndFields() {
        var draft = AccountDraft(name: "Old Locker", type: .other, currencyCode: "inr", enteredAmount: 5_000)
        draft.isHidden = true
        draft.excludeFromNetWealth = true
        draft.iconName = "tray"
        let base = Account(sortOrder: 9)
        let account = draft.applied(to: base)
        #expect(account.id == base.id)
        #expect(account.sortOrder == 9)
        #expect(account.isHidden)
        #expect(!account.includeInNetWorth)
        #expect(account.name == "Old Locker")
        #expect(account.currencyCode == "INR")
        #expect(account.iconName == "tray")
    }

    @Test("Every type has a default icon from the curated set")
    func defaultIcons() {
        for type in AccountType.allCases {
            #expect(AccountIcon.all.contains(AccountIcon.default(for: type)))
        }
        #expect(AccountIcon.default(for: .creditCard).symbolName == "creditcard")
        #expect(AccountIcon.default(for: .loan).symbolName == "percent")
        #expect(AccountIcon.resolved(nil, for: .cash) == AccountIcon.default(for: .cash))
        #expect(
            AccountIcon.resolved("chart.line.uptrend.xyaxis", for: .cash).symbolName == "chart.line.uptrend.xyaxis"
        )
    }

    @Test("Every supported currency code is listed once")
    func currencyCodes() {
        let codes = CurrencyCode.allCodes
        #expect(codes.contains("INR") && codes.contains("JPY") && codes.contains("KWD"))
        #expect(Set(codes).count == codes.count)
        #expect(codes == codes.sorted())
    }

    @Test("Picker codes drop ISO fund, test and metal codes but stay valid for stored data")
    func circulatingCodes() throws {
        let codes = CurrencyCode.circulatingCodes
        #expect(codes == codes.sorted())
        #expect(Set(codes).isSubset(of: Set(CurrencyCode.allCodes)))
        for code in ["USN", "UYI", "UYW", "BOV", "CHE", "CHW", "CLF", "COU", "MXV"] {
            #expect(!codes.contains(code))
            #expect(try CurrencyCode.validate(code) == code)
        }
        #expect(codes.contains("INR") && codes.contains("XAF") && codes.contains("XCD"))
    }
}
