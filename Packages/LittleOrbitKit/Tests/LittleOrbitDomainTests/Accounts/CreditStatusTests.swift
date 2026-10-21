import Foundation
import LittleOrbitDomain
import Testing

/// D52 and D104 in #20: available credit for credit cards with a limit.
@Suite("Available credit")
struct CreditStatusTests {
    private func card(limit: String?, show: Bool = true, type: AccountType = .creditCard) -> Account {
        Account(
            name: "Travel Card",
            type: type,
            currencyCode: "INR",
            creditLimit: limit.flatMap { Decimal(string: $0) },
            showAvailableCredit: show,
        )
    }

    @Test("Limit 1,00,000 with 30,000 owed has 70,000 available")
    func limitMinusOwed() throws {
        let status = try #require(card(limit: "100000").creditStatus(balance: -30_000))
        #expect(status.available == 70_000)
        #expect(status.limit == 100_000)
        #expect(status.overLimitBy == nil)
    }

    @Test("Nothing owed shows the whole limit")
    func nothingOwed() throws {
        let status = try #require(card(limit: "100000").creditStatus(balance: 0))
        #expect(status.available == 100_000)
    }

    @Test("Over the limit shows 0 available and the amount over")
    func overLimit() throws {
        let status = try #require(card(limit: "100000").creditStatus(balance: -105_000))
        #expect(status.available == 0)
        #expect(status.overLimitBy == 5_000)
    }

    @Test("A balance in credit adds to the limit")
    func inCredit() throws {
        let status = try #require(card(limit: "50000").creditStatus(balance: 2_000))
        #expect(status.available == 52_000)
        #expect(status.overLimitBy == nil)
    }

    @Test("No limit, switched off, loans and asset accounts show nothing")
    func hiddenCases() {
        #expect(card(limit: nil).creditStatus(balance: -30_000) == nil)
        #expect(card(limit: "100000", show: false).creditStatus(balance: -30_000) == nil)
        #expect(card(limit: "800000", type: .loan).creditStatus(balance: -800_000) == nil)
        let checking = Account(type: .checking)
        #expect(checking.creditStatus(balance: 20) == nil)
    }

    @Test("availableCredit(balance:) follows the same rules")
    func legacyAccessor() {
        #expect(card(limit: "50000").availableCredit(balance: 2_000) == 52_000)
        #expect(card(limit: "100000").availableCredit(balance: -105_000) == 0)
        #expect(card(limit: "800000", type: .loan).availableCredit(balance: -1) == nil)
    }
}
