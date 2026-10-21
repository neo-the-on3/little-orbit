import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// The accounts list view model against fake use cases: it only maps their results and forwards user actions.
@MainActor
@Suite("Accounts home with fake use cases")
struct AccountsViewModelFakeTests {
    private func summary(_ account: Account, balance: Decimal) -> AccountSummary {
        AccountSummary(account: account, balance: balance, creditStatus: nil, hasTransactions: false)
    }

    private func model(_ fake: FakeAccountUseCases) -> AccountsViewModel {
        let model = AccountsViewModel(useCases: fake.useCases, locale: FeatureFixture.india)
        model.load()
        return model
    }

    @Test("Rows and net wealth come from the use cases")
    func mapsResults() {
        let fake = FakeAccountUseCases()
        let wallet = Account(name: "Corner Wallet", type: .cash, currencyCode: "INR")
        fake.listing = AccountListing(assets: [summary(wallet, balance: 1_500)], totalCount: 1)
        fake.totals = [CurrencyTotal(currencyCode: "INR", amount: 1_500)]
        let model = model(fake)
        #expect(model.assets.map(\.name) == ["Corner Wallet"])
        #expect(!model.isFirstRun)
        #expect(model.netWealthSummary == "₹1,500.00")
    }

    @Test("A failing listing shows an error instead of crashing")
    func listingError() {
        let fake = FakeAccountUseCases()
        fake.listingError = FakeAccountUseCases.Failure()
        let model = model(fake)
        #expect(model.errorMessage == "Something went wrong saving your change. Please try again.")
    }

    @Test("Reorder, hide and delete are forwarded to their use cases")
    func forwardsActions() throws {
        let fake = FakeAccountUseCases()
        let first = Account(name: "A", type: .savings, currencyCode: "INR")
        let second = Account(name: "B", type: .savings, currencyCode: "INR")
        fake.listing = AccountListing(
            assets: [summary(first, balance: 0), summary(second, balance: 0)],
            totalCount: 2,
        )
        let model = model(fake)
        let confirmation = AccountDeleteConfirmation(model: model)
        model.move(in: .assets, fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(
            fake.moves == [
                .init(group: .assets, shown: [first.id, second.id], fromOffsets: IndexSet(integer: 1), toOffset: 0)
            ]
        )
        model.setHidden(true, accountID: second.id)
        #expect(fake.updatedIDs == [second.id])
        confirmation.request(accountID: first.id)
        #expect(confirmation.prompt != nil)
        confirmation.confirm()
        #expect(fake.deletedIDs == [first.id])
    }
}
