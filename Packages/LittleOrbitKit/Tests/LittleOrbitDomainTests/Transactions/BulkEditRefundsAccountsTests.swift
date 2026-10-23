import Foundation
import LittleOrbitDomain
import Testing

/// #34's bulk edit rules: refunds turn Category off (D222.4). The sample data is this ticket's own.
@Suite("Bulk edit: refunds and Account rules (#34)")
struct BulkEditRefundsAccountsTests {
    private static let india = "Asia/Kolkata"
    private let savings = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR")
    private let groceryCash = Account(name: "Grocery Cash", type: .cash, currencyCode: "INR")
    private var accounts: [Account] { [savings, groceryCash] }

    private func date(_ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: Self.india)!
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }

    private func row(_ type: TransactionType, _ amount: Decimal, in account: Account? = nil, day: Int = 1)
        -> Transaction
    {
        Transaction(
            type: type,
            amount: amount,
            date: date(day),
            timeZoneID: Self.india,
            accountID: (account ?? savings).id,
            createdAt: date(day),
        )
    }

    private func transfer(_ amount: Decimal, to destination: Account) -> Transaction {
        var transfer = row(.transfer, amount)
        transfer.transferAccountID = destination.id
        return transfer
    }

    private func refund(_ amount: Decimal, of expense: Transaction?) -> Transaction {
        var refund = row(.income, amount, day: 6)
        refund.isRefund = true
        refund.refundOfID = expense?.id
        return refund
    }

    /// 2 expenses and 1 income in Everyday Savings (INR).
    private var plain: [Transaction] { [row(.expense, 500), row(.expense, 200), row(.income, 900)] }

    // MARK: Refunds and Category (D222.4)

    @Test("D222.4: any refund, linked or orphaned, turns Category off, ahead of mixed types and transfers")
    func refundsTurnOffCategory() {
        let expense = row(.expense, 1_000)
        let linked = refund(300, of: expense)
        let orphaned = refund(80, of: nil)
        let income = row(.income, 500)
        let move = transfer(50, to: groceryCash)
        #expect(BulkEditRules.categoryAvailability(for: [orphaned, income, move]) == .includesRefunds)
        #expect(BulkEditRules.categoryAvailability(for: plain.prefix(2) + [linked]) == .includesRefunds)
        #expect(BulkEditRules.categoryAvailability(for: [income, income, orphaned]) == .includesRefunds)
        #expect(BulkEditRules.categoryAvailability(for: [move, linked]) == .includesRefunds)
        #expect(BulkEditRules.categoryAvailability(for: [linked]) == .includesRefunds)
        #expect(BulkEditRules.categoryAvailability(for: [income, move]) == .mixedTypes, "Without a refund, as before")
    }

    @Test("D222.4: with a refund selected, a category change applies to no row, and the rest still apply")
    func refundSelectionKeepsCategories() {
        let selection = [row(.income, 500), refund(300, of: nil)]
        let bakery = UUID()
        var changes = BulkEditChanges()
        changes.categoryID = .some(UUID())
        changes.payeeID = .some(bakery)
        let result = BulkEditRules.apply(changes, to: selection, accounts: accounts, timeZoneID: Self.india)
        #expect(zip(result, selection).allSatisfy { $0.categoryID == $1.categoryID })
        #expect(result.allSatisfy { $0.payeeID == bakery })
    }
}
