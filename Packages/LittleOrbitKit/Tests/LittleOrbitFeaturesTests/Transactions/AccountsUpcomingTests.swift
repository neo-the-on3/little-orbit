import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

@MainActor
@Suite("Accounts home with Upcoming transactions")
struct AccountsUpcomingTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @Test("A transaction dated next month stays out of the list balance and net wealth until its day (D21)")
    func upcomingExcluded() throws {
        let repository = try F.repository([
            F.expense(500, on: F.date(2026, 10, 19)),
            F.expense(2_000, on: F.date(2026, 11, 20)),
        ])
        let model = AccountsViewModel(
            useCases: AccountUseCases(
                repository: repository,
                defaultCurrency: "INR",
                timeZone: F.zone,
                now: { F.now },
            ),
            locale: F.india,
        )
        model.load()
        #expect(model.row(id: F.savingsID)?.balanceText == "₹9,500.00")
        #expect(model.netWealth.first?.text == "₹10,500.00")

        let later = AccountsViewModel(
            useCases: AccountUseCases(
                repository: repository,
                defaultCurrency: "INR",
                timeZone: F.zone,
                now: { F.date(2026, 11, 20, 9) },
            ),
            locale: F.india,
        )
        later.load()
        #expect(later.row(id: F.savingsID)?.balanceText == "₹7,500.00")
    }

    @Test("Undo from the home screen reverts a new transaction and refreshes balances")
    func undoFromHome() throws {
        let repository = try F.repository()
        let model = AccountsViewModel(
            useCases: AccountUseCases(
                repository: repository,
                defaultCurrency: "INR",
                timeZone: F.zone,
                now: { F.now },
            ),
            locale: F.india,
        )
        let form = TransactionFormViewModel(
            useCases: TransactionUseCases(repository: repository),
            mode: .new(accountID: F.walletID),
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
        form.press(.digit(5))
        form.press(.digit(0))
        let change = try #require(form.save())
        model.load()
        #expect(model.row(id: F.walletID)?.balanceText == "₹950.00")
        let window = UndoTestSupport.undo(change, useCases: TransactionUseCases(repository: repository))
        model.load()
        #expect(window.history.canRedo)
        #expect(model.row(id: F.walletID)?.balanceText == "₹1,000.00")
    }
}
