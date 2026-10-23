import Foundation
import LittleOrbitDomain
import Testing

/// #34's bulk edit rules: refunds turn Category off (D222.4), and an Account change moves every row or none
/// (D223, D226, D227). The sample data is this ticket's own: Travel Card is a USD card here.
@Suite("Bulk edit: refunds and Account rules (#34)")
struct BulkEditRefundsAccountsTests {
    private static let india = "Asia/Kolkata"
    private let savings = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR")
    private let groceryCash = Account(name: "Grocery Cash", type: .cash, currencyCode: "INR")
    private let holidayFund = Account(name: "Holiday Fund", type: .savings, currencyCode: "INR")
    private let travelCard = Account(name: "Travel Card", type: .creditCard, currencyCode: "USD")
    private let yenPocket = Account(name: "Yen Pocket", type: .cash, currencyCode: "JPY")
    private var accounts: [Account] { [savings, groceryCash, holidayFund, travelCard, yenPocket] }

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

    private func transfer(_ amount: Decimal, from source: Account? = nil, to destination: Account) -> Transaction {
        var transfer = row(.transfer, amount, in: source)
        transfer.transferAccountID = destination.id
        return transfer
    }

    private func refund(_ amount: Decimal, of expense: Transaction?) -> Transaction {
        var refund = row(.income, amount, day: 6)
        refund.isRefund = true
        refund.refundOfID = expense?.id
        return refund
    }

    /// 2 expenses and 1 income in Everyday Savings (INR), as in P24.
    private var plain: [Transaction] { [row(.expense, 500), row(.expense, 200), row(.income, 900)] }

    private func rejection(moving rows: [Transaction], to account: Account) -> BulkEditRejection? {
        var changes = BulkEditChanges()
        changes.accountID = account.id
        do {
            _ = try BulkEditRules.apply(changes, to: rows, accounts: accounts, ledger: [])
            return nil
        } catch {
            return error
        }
    }

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
    func refundSelectionKeepsCategories() throws {
        let selection = [row(.income, 500), refund(300, of: nil)]
        let bakery = UUID()
        var changes = BulkEditChanges()
        changes.categoryID = .some(UUID())
        changes.payeeID = .some(bakery)
        let result = try BulkEditRules.apply(changes, to: selection, accounts: accounts, ledger: [])
        #expect(zip(result, selection).allSatisfy { $0.categoryID == $1.categoryID })
        #expect(result.allSatisfy { $0.payeeID == bakery })
    }

    // MARK: Account (D223, D226, D227)

    @Test("D223: a transfer moved to its own To account rejects the whole edit, with the count and account")
    func ownToAccount() {
        let rows = plain + [transfer(100, to: holidayFund)]
        #expect(rejection(moving: rows, to: holidayFund) == .ownToAccount(count: 1, accountID: holidayFund.id))
        #expect(
            rejection(moving: rows + [transfer(70, to: holidayFund)], to: holidayFund)
                == .ownToAccount(count: 2, accountID: holidayFund.id)
        )
        #expect(
            BulkEditRules.accountRejection(moving: rows, to: holidayFund.id, accounts: accounts)
                == .ownToAccount(count: 1, accountID: holidayFund.id),
            "The same check the popup can use",
        )
    }

    @Test("P24: rows in INR move to another INR account, every row, amounts unchanged, transfers included")
    func sameCurrencyMovesEveryRow() throws {
        let rows = plain + [transfer(100, to: holidayFund)]
        var changes = BulkEditChanges()
        changes.accountID = groceryCash.id
        let result = try BulkEditRules.apply(changes, to: rows, accounts: accounts, ledger: [])
        #expect(result.allSatisfy { $0.accountID == groceryCash.id })
        #expect(zip(result, rows).allSatisfy { $0.amount == $1.amount && $0.type == $1.type })
        #expect(result.last?.transferAccountID == holidayFund.id)
    }

    @Test("P25: an INR expense never moves to a USD account as the same number; the edit is rejected")
    func otherCurrencyRejected() {
        let expense = row(.expense, 500)
        #expect(
            rejection(moving: [expense], to: travelCard)
                == .otherCurrency(count: 1, currencyCode: "INR", accountID: travelCard.id)
        )
        #expect(
            rejection(moving: plain, to: travelCard)
                == .otherCurrency(count: 3, currencyCode: "INR", accountID: travelCard.id)
        )
        // A transfer by its From account, a refund and an expense with refunds follow the same rule (D226.2).
        let rows = plain + [transfer(100, to: holidayFund), refund(100, of: plain[0])]
        #expect(
            rejection(moving: rows, to: travelCard)
                == .otherCurrency(count: 5, currencyCode: "INR", accountID: travelCard.id)
        )
    }

    @Test("D227.2: mixed currencies name the account's currency and count the rows not in it")
    func mixedCurrencyCount() {
        let rupees = [row(.expense, 500), row(.expense, 200)]
        let dollars = row(.expense, 20, in: travelCard)
        let yen = row(.expense, 900, in: yenPocket)
        #expect(
            rejection(moving: [dollars] + rupees, to: travelCard)
                == .mixedCurrencies(count: 2, currencyCode: "USD", accountID: travelCard.id)
        )
        #expect(
            rejection(moving: [yen, dollars] + rupees, to: groceryCash)
                == .mixedCurrencies(count: 2, currencyCode: "INR", accountID: groceryCash.id)
        )
        #expect(
            rejection(moving: [yen, dollars], to: groceryCash)
                == .mixedCurrencies(count: 2, currencyCode: "INR", accountID: groceryCash.id),
            "No row in the account's currency",
        )
        #expect(
            rejection(moving: rupees, to: travelCard)
                == .otherCurrency(count: 2, currencyCode: "INR", accountID: travelCard.id),
            "One currency keeps D226.4",
        )
        #expect(rejection(moving: [dollars], to: travelCard) == nil, "Same currency moves")
    }

    @Test("D227.1 order: the To-account rule comes before currency")
    func checkOrder() {
        let usdTransfer = transfer(30, from: travelCard, to: holidayFund)
        let expense = row(.expense, 500)
        // Holiday Fund is the transfer's own To account, and the transfer is in USD: the To account wins.
        #expect(
            rejection(moving: [expense, usdTransfer], to: holidayFund)
                == .ownToAccount(count: 1, accountID: holidayFund.id)
        )
        #expect(
            rejection(moving: [usdTransfer, expense], to: groceryCash)
                == .mixedCurrencies(count: 1, currencyCode: "INR", accountID: groceryCash.id)
        )
        #expect(
            rejection(moving: [usdTransfer], to: groceryCash)
                == .otherCurrency(count: 1, currencyCode: "USD", accountID: groceryCash.id)
        )
        // Without an Account change, no account rule applies.
        var changes = BulkEditChanges()
        changes.details = .some("Trip")
        #expect(throws: Never.self) {
            _ = try BulkEditRules.apply(
                changes,
                to: [expense, usdTransfer],
                accounts: accounts,
                ledger: [],
            )
        }
    }
}
