import Foundation
import LittleOrbitDomain
import Testing

/// D7, D17, D22 and D53: one total per currency, default currency first, no conversion.
@Suite("Net wealth")
struct NetWealthTests {
    private let netWealth = ComputeNetWealth(defaultCurrency: "INR")

    @Test("The fixture totals ₹16,650.50 · €300.00 · $1,240.00, INR first")
    func fixtureTotals() throws {
        let totals = try netWealth(accounts: AccountFixture.all, transactions: [])
        #expect(
            totals == [
                CurrencyTotal(currencyCode: "INR", amount: Decimal(string: "16650.50")!),
                CurrencyTotal(currencyCode: "EUR", amount: 300),
                CurrencyTotal(currencyCode: "USD", amount: 1_240),
            ]
        )
    }

    @Test("Other currencies follow the default in code order")
    func ordering() throws {
        let totals = try netWealth(accounts: AccountFixture.all, transactions: [])
        #expect(totals.map(\.currencyCode) == ["INR", "EUR", "USD"])
    }

    @Test("Hidden accounts count unless excluded; excluded ones never count (D22)")
    func hiddenAndExcluded() throws {
        var locker = AccountFixture.oldLocker
        locker.isHidden = false
        let totals = try netWealth(accounts: [AccountFixture.longTermFund, locker], transactions: [])
        #expect(totals == [CurrencyTotal(currencyCode: "INR", amount: 20_000)])
    }

    @Test("A currency whose only accounts are excluded has no line")
    func excludedCurrencyDisappears() throws {
        var holiday = AccountFixture.holidayFund
        holiday.includeInNetWorth = false
        let totals = try netWealth(accounts: [AccountFixture.everydaySavings, holiday], transactions: [])
        #expect(totals.map(\.currencyCode) == ["INR"])
    }

    @Test("Credit cards count their balance, never the available credit (S77)")
    func creditUsesBalance() throws {
        let totals = try netWealth(accounts: [AccountFixture.travelCard], transactions: [])
        #expect(totals == [CurrencyTotal(currencyCode: "INR", amount: -30_000)])
    }

    @Test("Transactions move the totals")
    func transactionsCount() throws {
        let wallet = AccountFixture.cornerWallet
        let totals = try netWealth(accounts: [wallet], transactions: [AccountFixture.expense(1_000, from: wallet)])
        #expect(totals.first?.amount == Decimal(string: "650.50"))
    }

    @Test("No accounts has no totals")
    func empty() throws {
        #expect(try netWealth(accounts: [], transactions: []).isEmpty)
    }
}
