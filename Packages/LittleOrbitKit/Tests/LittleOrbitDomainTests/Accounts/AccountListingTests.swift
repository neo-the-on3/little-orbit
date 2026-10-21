import Foundation
import LittleOrbitDomain
import Testing

@Suite("Account list")
struct AccountListingTests {
    private let list = ListAccounts()

    @Test("Visible accounts are split into Assets and Credit in the user's order")
    func groupsAndOrder() throws {
        let listing = try list(
            accounts: AccountFixture.all.reversed(),
            transactions: [],
            showHidden: false,
            today: AccountFixture.today,
        )
        #expect(
            listing.assets.map(\.account.name) == ["Everyday Savings", "Corner Wallet", "Holiday Fund", "Euro Pocket"]
        )
        #expect(listing.credit.map(\.account.name) == ["Travel Card"])
        #expect(listing.hiddenCount == 2)
        #expect(listing.totalCount == 7)
        #expect(!listing.isEmpty)
    }

    @Test("Show hidden lists hidden accounts in their own place (D109)")
    func showHidden() throws {
        let listing = try list(
            accounts: AccountFixture.all,
            transactions: [],
            showHidden: true,
            today: AccountFixture.today,
        )
        #expect(
            listing.assets.map(\.account.name) == [
                "Everyday Savings", "Corner Wallet", "Long Term Fund", "Old Locker", "Holiday Fund", "Euro Pocket",
            ]
        )
        #expect(listing.hiddenCount == 2)
    }

    @Test("Each row carries its balance, credit status and whether it has transactions")
    func summaries() throws {
        let card = AccountFixture.travelCard
        let wallet = AccountFixture.cornerWallet
        let listing = try list(
            accounts: [card, wallet],
            transactions: [AccountFixture.expense(1_000, from: wallet)],
            showHidden: false,
            today: AccountFixture.today,
        )
        let walletRow = try #require(listing.assets.first)
        #expect(walletRow.balance == Decimal(string: "650.50"))
        #expect(walletRow.hasTransactions)
        #expect(walletRow.creditStatus == nil)
        let cardRow = try #require(listing.credit.first)
        #expect(cardRow.balance == -30_000)
        #expect(!cardRow.hasTransactions)
        #expect(cardRow.creditStatus?.available == 70_000)
    }

    @Test("Being only a transfer's destination counts as having transactions (D114)")
    func transferDestinationCounts() throws {
        let source = AccountFixture.everydaySavings
        let destination = AccountFixture.cornerWallet
        let listing = try list(
            accounts: [source, destination],
            transactions: [AccountFixture.transfer(500, from: source, to: destination)],
            showHidden: false,
            today: AccountFixture.today,
        )
        #expect(listing.assets.allSatisfy { $0.hasTransactions })
    }

    @Test("No accounts is the first-run state")
    func empty() throws {
        let listing = try list(accounts: [], transactions: [], showHidden: false, today: AccountFixture.today)
        #expect(listing.isEmpty)
        #expect(listing.assets.isEmpty && listing.credit.isEmpty)
    }

    @Test("Only hidden accounts is not the first-run state")
    func onlyHidden() throws {
        let listing = try list(
            accounts: [AccountFixture.longTermFund],
            transactions: [],
            showHidden: false,
            today: AccountFixture.today,
        )
        #expect(!listing.isEmpty)
        #expect(listing.hiddenCount == 1)
    }
}
