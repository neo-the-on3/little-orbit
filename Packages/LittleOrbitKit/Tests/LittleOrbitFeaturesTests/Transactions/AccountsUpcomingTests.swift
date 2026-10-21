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
}
