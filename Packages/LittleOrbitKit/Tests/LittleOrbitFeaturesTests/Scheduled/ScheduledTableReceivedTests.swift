import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// The Mac Scheduled Table's Amount cell help (D364, the #205 merge gate on #207): a transfer between currencies
/// adds "received ‹amount›" in To's currency to the amount sent, from the same catalog entry as the iOS row; every
/// other row's help is the amount alone. The cell's text stays the amount sent. Made-up data; today is 20 Oct 2026.
@MainActor
@Suite("Mac Scheduled Table: received amount in the Amount help (D364)")
struct ScheduledTableReceivedTests {
    private static let wallet = Account(name: "USD Wallet", currencyCode: "USD", sortOrder: 2)

    private func rows(_ scene: ScheduledScene) -> [String: ScheduledTableRow] {
        let list = ScheduledListViewModel(
            useCases: scene.useCases,
            locale: Locale(identifier: "en_IN"),
            platform: .macOS,
        )
        list.load()
        return Dictionary(uniqueKeysWithValues: list.tableSections.flatMap(\.rows).map { ($0.name, $0) })
    }

    private func transfer(_ scene: ScheduledScene, _ name: String, to account: Account, received: Decimal?)
        -> ScheduledItem
    {
        var item = scene.item(name, day: 1, month: 11)
        item.type = .transfer
        item.amount = 1_000
        item.categoryID = nil
        item.transferAccountID = account.id
        item.destinationAmount = received
        return item
    }

    @Test("A transfer between currencies gives the received help; a same-currency transfer and an expense give none")
    func helpOnlyBetweenCurrencies() throws {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(Self.wallet)
        try scene.add(
            transfer(scene, "Fund USD Wallet", to: Self.wallet, received: 12),
            transfer(scene, "Top up the fund", to: scene.fund, received: nil),
            scene.item("Rent", day: 1, month: 11),
        )
        let rows = rows(scene)
        let cross = try #require(rows["Fund USD Wallet"])
        #expect(cross.received == "received $12.00")
        #expect(cross.amountHelp == "\(cross.amount) · received $12.00")
        #expect(!cross.amount.contains("12.00"), "The cell still shows the amount sent")
        let same = try #require(rows["Top up the fund"])
        #expect(same.received == nil)
        #expect(same.amountHelp == same.amount)
        let rent = try #require(rows["Rent"])
        #expect(rent.received == nil)
        #expect(rent.amountHelp == rent.amount)
    }

    @Test("A stored received amount on a transfer whose To is now in From's currency gives no help")
    func storedReceivedSameCurrency() throws {
        let scene = try ScheduledScene()
        try scene.repository.saveAccount(Self.wallet)
        try scene.add(transfer(scene, "Fund USD Wallet", to: Self.wallet, received: 12))
        // The store refuses this change now (D410.1); data saved before D410 can still hold it.
        var wallet = Self.wallet
        wallet.currencyCode = "INR"
        var ledger = try scene.repository.ledgerSnapshot()
        ledger.accounts = ledger.accounts.map { $0.id == wallet.id ? wallet : $0 }
        try scene.repository.replaceLedger(with: ledger)
        let row = try #require(rows(scene)["Fund USD Wallet"])
        #expect(row.received == nil)
        #expect(row.amountHelp == row.amount)
    }
}
