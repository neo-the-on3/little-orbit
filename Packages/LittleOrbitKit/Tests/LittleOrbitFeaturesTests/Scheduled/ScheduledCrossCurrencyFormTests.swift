import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// The Scheduled form's transfer between currencies (#197 item 9, #26 S4, D17), reusing #23's design: a Received
/// amount and the read-only rate. Made-up data; today is 20 Oct 2026. The wording is the same on iOS and the Mac.
@MainActor
@Suite("Scheduled transfers between currencies: the form (#197)")
struct ScheduledCrossCurrencyFormTests {
    private static let wallet = Account(name: "USD Wallet", currencyCode: "USD", sortOrder: 2)
    private static let yen = Account(name: "Tokyo Wallet", currencyCode: "JPY", sortOrder: 3)

    private func scene() throws -> ScheduledScene {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(Self.wallet)
        try scene.repository.saveAccount(Self.yen)
        return scene
    }

    private func newTransfer(_ scene: ScheduledScene, platform: ScheduledPlatform) throws
        -> (ScheduledListViewModel, ScheduledFormViewModel)
    {
        let list = scene.list(scene.feature(), platform: platform)
        list.load()
        list.openNew()
        let form = try #require(list.form)
        form.type = .transfer
        form.details = "Fund USD Wallet"
        form.amountText = "1,000"
        return (list, form)
    }

    @Test("D364: on iOS a transfer between currencies adds “received ‹amount›” to the row's subtitle")
    func receivedInRowSubtitle() throws {
        let scene = try scene()
        let (list, form) = try newTransfer(scene, platform: .iOS)
        form.transferAccountID = Self.wallet.id
        form.receivedText = "12"
        #expect(form.save())
        // A same-currency transfer beside it shows no received text.
        list.openNew()
        let same = try #require(list.form)
        same.type = .transfer
        same.details = "Top up the fund"
        same.amountText = "500"
        same.transferAccountID = scene.fund.id
        #expect(same.save())
        list.load()
        let rows = list.dueTodayRows
        let crossRow = try #require(rows.first { $0.title == "Fund USD Wallet" })
        let parts = crossRow.detail.components(separatedBy: " · ")
        let received = try #require(parts.last)
        #expect(received.hasPrefix("received "))
        #expect(received.contains("12.00"))
        #expect(received.contains("$"), "In To's currency")
        #expect(crossRow.amount.contains("1,000"), "The row's amount stays the amount sent")
        #expect(!crossRow.amount.contains("12.00"))
        let sameRow = try #require(rows.first { $0.title == "Top up the fund" })
        #expect(!sameRow.detail.contains("received"))
    }

    @Test(
        "S4: To in another currency asks for Received, shows the rate, and keeps both amounts",
        arguments: [
            ScheduledPlatform.iOS, .macOS,
        ],
    )
    func bothAmounts(platform: ScheduledPlatform) throws {
        let scene = try scene()
        let wallet = Self.wallet
        let (list, form) = try newTransfer(scene, platform: platform)
        #expect(form.transferAccountID == scene.fund.id, "The first other account, as before")
        #expect(!form.needsReceivedAmount)
        #expect(form.toChoices.map(\.name) == ["Long Term Fund · INR", "USD Wallet · USD", "Tokyo Wallet · JPY"])
        #expect(form.accountChoices.first?.name == "Everyday Savings · INR")
        form.transferAccountID = wallet.id
        #expect(form.needsReceivedAmount)
        #expect(form.receivedLabel == "Received")
        #expect(form.receivedCurrencyCode == "USD")
        #expect(form.rateText == nil)
        #expect(!form.save())
        #expect(form.receivedError == "Enter the amount received in USD.")
        form.receivedText = "0"
        #expect(!form.save())
        #expect(form.receivedError == "Enter the amount received in USD.")
        form.receivedText = "12"
        let rate = try #require(form.rateText)
        #expect(rate.hasPrefix("1 USD = "))
        #expect(rate.contains("83.33"))
        #expect(rate.hasSuffix(" · worked out from the two amounts"))
        #expect(form.save())
        #expect(form.receivedError == nil)
        list.load()
        let row = try #require(list.dueTodayRows.first)
        let stored = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        #expect(stored.amount == 1_000)
        #expect(stored.destinationAmount == 12)
        #expect(stored.transferAccountID == wallet.id)
        // The item screen lists the amount received; Pay Now records both amounts as one transfer.
        let received = list.detail(row.itemID)?.facts.first { $0.label == "Received" }
        #expect(received?.value.contains("12.00") == true)
        list.payNow(row)
        let posted = try #require(scene.recorded.first)
        #expect(posted.amount == 1_000)
        #expect(posted.destinationAmount == 12)
        #expect(scene.recorded.count == 1)
    }

    @Test("Received follows To's currency: JPY takes no decimals")
    func receivedDecimals() throws {
        let scene = try scene()
        let yen = Self.yen
        let (_, form) = try newTransfer(scene, platform: .iOS)
        form.transferAccountID = yen.id
        form.receivedText = "150.5"
        #expect(!form.save())
        #expect(form.receivedError == "JPY amounts have no decimal places.")
        form.receivedText = "abc"
        #expect(!form.save())
        #expect(form.receivedError?.hasPrefix("Enter an amount like ") == true)
        form.receivedText = "150"
        #expect(form.save())
        #expect(try scene.repository.scheduleLedger().scheduledItems.first?.destinationAmount == 150)
    }

    @Test("Editing shows the stored Received; changing To back to INR drops it on save")
    func backToOneCurrency() throws {
        let scene = try scene()
        let wallet = Self.wallet
        let (list, form) = try newTransfer(scene, platform: .iOS)
        form.transferAccountID = wallet.id
        form.receivedText = "12"
        #expect(form.save())
        list.load()
        list.openEditor(try #require(list.dueTodayRows.first?.itemID))
        let edit = try #require(list.form)
        #expect(edit.needsReceivedAmount)
        #expect(
            edit.receivedText
                == MoneyFormatter(locale: Locale(identifier: "en_IN")).inputString(12, currencyCode: "USD")
        )
        edit.transferAccountID = scene.fund.id
        #expect(!edit.needsReceivedAmount)
        #expect(edit.rateText == nil)
        #expect(edit.save())
        let stored = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        #expect(stored.transferAccountID == scene.fund.id)
        #expect(stored.destinationAmount == nil)
    }

    @Test(
        "Tech Architect NB 2: a To in another currency clears the typed Received; one in the same currency keeps it",
        arguments: [
            ScheduledPlatform.iOS, .macOS,
        ],
    )
    func toCurrencyChanges(platform: ScheduledPlatform) throws {
        let scene = try scene()
        let card = Account(name: "USD Card", currencyCode: "USD", sortOrder: 4)
        try scene.repository.saveAccount(card)
        let (_, form) = try newTransfer(scene, platform: platform)
        form.transferAccountID = Self.wallet.id
        form.receivedText = "12"
        form.transferAccountID = card.id
        #expect(form.receivedText == "12", "USD to USD: still $12")
        #expect(form.rateText != nil)
        form.transferAccountID = Self.yen.id
        #expect(form.receivedText.isEmpty, "12 must not become ¥12")
        #expect(form.rateText == nil)
        #expect(!form.save())
        #expect(form.receivedError == "Enter the amount received in JPY.")
        form.transferAccountID = Self.wallet.id
        #expect(form.receivedError == nil, "The old currency's error goes with it")
        form.receivedText = "12"
        form.transferAccountID = scene.fund.id
        #expect(form.receivedText.isEmpty, "Back to From's currency drops it")
        #expect(form.save())
        let stored = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        #expect(stored.destinationAmount == nil)
    }

    @Test("From and To are never the same account, in any currency")
    func fromChanges() throws {
        let scene = try scene()
        let wallet = Self.wallet
        let (_, form) = try newTransfer(scene, platform: .iOS)
        form.transferAccountID = wallet.id
        form.accountID = wallet.id
        #expect(form.transferAccountID != wallet.id)
        #expect(!form.toChoices.contains { $0.id == wallet.id })
        form.type = .expense
        #expect(form.accountChoices.first?.name == "Everyday Savings", "Only a transfer names the currency")
    }
}
