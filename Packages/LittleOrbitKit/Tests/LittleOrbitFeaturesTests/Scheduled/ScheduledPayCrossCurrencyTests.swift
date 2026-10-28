import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// D415 on #201 (Product Manager, 6471912890): the custom Pay sheet between currencies. Amount is in From's currency
/// and Received in To's; both are required and above zero, and Record is disabled until both read. Received is
/// prefilled with the item's amount received when it has one, else left empty, never worked out from a rate. A Pay
/// in one currency is unchanged and has no Received. Made-up data; today is 20 Oct 2026.
@MainActor
@Suite("Custom Pay between currencies (D415)")
struct ScheduledPayCrossCurrencyTests {
    private let usdCard = Account(name: "USD Card", type: .cash, currencyCode: "USD", sortOrder: 3)

    private func open(_ scene: ScheduledScene) throws -> ScheduledPayViewModel {
        let list = scene.list(scene.feature(), platform: .iOS)
        list.load()
        list.openCustomPay(try #require(list.overdueRows.first))
        return try #require(list.payment)
    }

    /// Rent Share between currencies, ₹1,000 received as $12, and its Pay sheet.
    private func crossSheet(_ scene: ScheduledScene) throws -> ScheduledPayViewModel {
        try scene.addRentShare()
        return try open(scene)
    }

    /// Top Up Fund, ₹500 a month from Everyday Savings to Long Term Fund, both INR, due 1 Oct; and its Pay sheet.
    private func sameCurrencySheet(_ scene: ScheduledScene) throws -> ScheduledPayViewModel {
        try scene.repository.saveAccount(usdCard)
        var topUp = scene.item("Top Up Fund", day: 1, month: 10)
        topUp.type = .transfer
        topUp.amount = 500
        topUp.categoryID = nil
        topUp.transferAccountID = scene.fund.id
        try scene.add(topUp)
        return try open(scene)
    }

    @Test("D285.5 gate: Amount posts to From in INR and Received to To in USD, on one transaction")
    func postsBothLegs() throws {
        let scene = try ScheduledScene()
        let sheet = try crossSheet(scene)
        sheet.amountText = "2000"
        sheet.receivedText = "24"
        #expect(sheet.canRecord)
        #expect(sheet.record())
        let paid = try #require(scene.recorded.first)
        let accounts = try scene.repository.accounts()
        let source = try #require(accounts.first { $0.id == paid.accountID })
        let target = try #require(accounts.first { $0.id == paid.transferAccountID })
        #expect(source.id == scene.account.id && source.currencyCode == "INR")
        #expect(paid.amount == 2_000, "Amount, in From's INR")
        #expect(target.name == "Travel Card" && target.currencyCode == "USD")
        #expect(paid.destinationAmount == 24, "Received, in To's USD")
    }

    @Test("D285.5 gate: a Pay in one currency has no Received field and records as before")
    func sameCurrencyHasNoReceived() throws {
        let scene = try ScheduledScene()
        let sheet = try sameCurrencySheet(scene)
        #expect(!sheet.needsReceivedAmount)
        #expect(sheet.receivedHint == nil && sheet.amountHint == nil)
        #expect(sheet.canRecord)
        sheet.amountText = "0"
        #expect(sheet.canRecord, "Unchanged: Record stays enabled and shows the error")
        #expect(!sheet.record())
        #expect(sheet.amountError == ScheduledText.enterAmount)
        sheet.amountText = "600"
        #expect(sheet.record())
        let paid = try #require(scene.recorded.first)
        #expect(paid.amount == 600 && paid.destinationAmount == nil)
    }

    @Test("Received is prefilled with the item's $12")
    func prefillsItemsReceived() throws {
        let scene = try ScheduledScene()
        let sheet = try crossSheet(scene)
        #expect(sheet.receivedText == "12.00" || sheet.receivedText == "12")
        #expect(sheet.canRecord, "Both prefilled amounts read, so Record is enabled as the sheet opens")
    }

    @Test("No amount received on the item (From changed to USD Card): Received is empty, no rate guessed")
    func emptyWithoutItemsReceived() throws {
        let scene = try ScheduledScene()
        let sheet = try sameCurrencySheet(scene)
        sheet.accountID = usdCard.id
        #expect(sheet.needsReceivedAmount)
        #expect(sheet.receivedText.isEmpty)
        #expect(sheet.receivedCurrencyCode == "INR")
        #expect(sheet.receivedHint == "Enter the amount received in INR.")
        #expect(!sheet.canRecord)
    }

    @Test(
        "Record stays disabled while Received is empty, 0 or unreadable, or Amount is 0, and enables once both read",
        arguments: [
            ("", "2000", false), ("0", "2000", false), ("0.00", "2000", false), ("1.234", "2000", false),
            ("abc", "2000", false), ("24", "0", false), ("24", "", false), ("24", "2000", true),
        ],
    )
    func recordWaitsForBoth(received: String, amount: String, enabled: Bool) throws {
        let scene = try ScheduledScene()
        let sheet = try crossSheet(scene)
        sheet.receivedText = received
        sheet.amountText = amount
        #expect(sheet.canRecord == enabled, "Received \(received), Amount \(amount)")
        #expect((sheet.receivedHint == nil && sheet.amountHint == nil) == enabled)
    }

    @Test("Received 0: the hint asks for the amount received, and Record anyway pays nothing")
    func zeroReceived() throws {
        let scene = try ScheduledScene()
        let sheet = try crossSheet(scene)
        sheet.receivedText = "0"
        #expect(sheet.receivedHint == "Enter the amount received in USD.")
        #expect(!sheet.record())
        #expect(scene.recorded.isEmpty)
    }

    @Test("Each From choice is the account's name and its currency code, as on the Scheduled form (#207)")
    func fromChoicesNameCurrency() throws {
        let scene = try ScheduledScene()
        let sheet = try crossSheet(scene)
        let names = sheet.accountChoices.map(\.name)
        #expect(names.contains("Everyday Savings · INR"))
        #expect(names.contains("Long Term Fund · INR"))
        #expect(!names.contains { $0.hasPrefix("Travel Card") }, "To is never From")
    }

    // MARK: Amount in From's currency (Tester's iPhone and iPad run at 7c8a893, 6472280527)

    @Test("From switched to USD Card: Amount is in USD, reformatted, and the footer names both currencies")
    func amountFollowsFrom() throws {
        let scene = try ScheduledScene()
        let sheet = try sameCurrencySheet(scene)
        #expect(sheet.amountCurrencyCode == "INR")
        #expect(sheet.amountFooter == "Scheduled amount: ₹500.00.", "One currency: unchanged")
        sheet.accountID = usdCard.id
        #expect(sheet.amountCurrencyCode == "USD")
        #expect(sheet.amountText == "500.00")
        #expect(sheet.amountFooter == "Scheduled amount: ₹500.00, in INR. The amount paid is in USD.")
        sheet.amountText = "6.25"
        sheet.receivedText = "520"
        #expect(sheet.record())
        let paid = try #require(scene.recorded.first)
        #expect(paid.accountID == usdCard.id && paid.amount == 6.25, "Posted from USD Card in USD")
        #expect(paid.destinationAmount == 520, "Received in To's INR")
    }

    @Test("Amount reads in From's decimals: 1.234 is too many for INR, and fine once From is in KWD")
    func amountDecimalsFollowFrom() throws {
        let scene = try ScheduledScene()
        let dinar = Account(name: "Dinar Card", type: .cash, currencyCode: "KWD", sortOrder: 4)
        try scene.repository.saveAccount(dinar)
        let sheet = try sameCurrencySheet(scene)
        sheet.amountText = "1.234"
        if case .success = sheet.readAmount() {
            Issue.record("1.234 read in INR")
        }
        sheet.accountID = dinar.id
        #expect(sheet.amountText == "1.234", "Kept as typed: it reads in KWD")
        #expect(sheet.amountCurrencyCode == "KWD")
        #expect(try sheet.readAmount().get() == Decimal(string: "1.234"))
    }

    @Test("From switched to a JPY account: ₹500.00 as typed becomes 500, in yen's decimals; then KWD, 500.000")
    func amountReformatsInFromsDecimals() throws {
        let scene = try ScheduledScene()
        let yen = Account(name: "Yen Card", type: .cash, currencyCode: "JPY", sortOrder: 4)
        let dinar = Account(name: "Dinar Card", type: .cash, currencyCode: "KWD", sortOrder: 5)
        try scene.repository.saveAccount(yen)
        try scene.repository.saveAccount(dinar)
        let sheet = try sameCurrencySheet(scene)
        sheet.accountID = yen.id
        #expect(sheet.amountText == "500")
        sheet.accountID = dinar.id
        #expect(sheet.amountText == "500.000")
        sheet.amountText = "1.234"
        sheet.accountID = yen.id
        #expect(sheet.amountText == "1.234", "Not exact in yen, so kept as typed for its hint")
        #expect(sheet.amountHint != nil)
    }

    @Test("Amount and Received have their own accessibility labels")
    func accessibilityLabels() throws {
        let scene = try ScheduledScene()
        let sheet = try crossSheet(scene)
        #expect(sheet.amountAccessibilityLabel == "Amount paid")
        #expect(sheet.receivedAccessibilityLabel == "Amount received")
    }
}
