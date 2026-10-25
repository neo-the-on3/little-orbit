import Foundation
import LittleOrbitDomain
import Testing

/// The report and budgets count spending the same way (Tech Architect's NB3 on #185): for the same month, every
/// report row equals the budgets' `CategorySpending` for that category and currency.
@Suite("Spending report agrees with budgets (#27 core, #25)")
struct SpendingReportAgreementTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias R = ReportFixture  // swiftlint:disable:this type_name

    @Test(
        "Row amounts match the budgets' CategorySpending for the same month: splits, refunds, Uncategorised, USD, deleted accounts and categories, and future-dated items (NB3, D319.2)"
    )
    func matchesCategorySpending() {
        let split = R.expense(1_500, R.groceries, on: F.date(2026, 10, 9))
        var deletedTransaction = R.expense(70, R.rent, on: F.date(2026, 10, 5))
        deletedTransaction.deletedAt = F.date(2026, 10, 6)
        let transactions = [
            R.expense(1_000, R.groceries, on: F.date(2026, 10, 3)),
            R.refund(250, R.groceries, on: F.date(2026, 10, 4)),
            R.expense(80, R.groceries, on: F.date(2026, 10, 3), account: F.usdID),
            R.expense(300, nil, on: F.date(2026, 10, 2)),
            split,
            R.expense(400, R.household, on: F.date(2026, 10, 7)),
            R.expense(200, R.rent, on: F.date(2026, 10, 8), account: F.walletID),
            deletedTransaction,
            R.expense(900, R.rent, on: F.date(2026, 10, 28)),
            R.expense(60, R.rent, on: F.date(2026, 11, 1)),
        ]
        let lines = [
            TransactionSplit(transactionID: split.id, categoryID: R.groceries.id, amount: 1_000),
            TransactionSplit(transactionID: split.id, categoryID: R.electronics.id, amount: 500),
        ]
        var snapshot = R.snapshot(transactions, splits: lines)
        snapshot.categories = snapshot.categories.map { category in
            var copy = category
            if copy.id == R.household.id {
                copy.deletedAt = F.date(2026, 10, 10)
            }
            return copy
        }
        snapshot.accounts = snapshot.accounts.map { account in
            var copy = account
            if copy.id == F.walletID {
                copy.deletedAt = F.date(2026, 10, 10)
            }
            return copy
        }
        // Budgets key spending by the stored category; the report shows a gone category as Uncategorised.
        let live = Set(snapshot.categoriesVisible().map(\.id))
        var budgets: [CategoryCurrency: Decimal] = [:]
        let october = CategorySpending.spending(in: snapshot, from: F.day(2026, 10, 1), through: F.day(2026, 10, 31))
        for (key, amount) in october {
            let shown = key.categoryID.flatMap { live.contains($0) ? $0 : nil }
            budgets[CategoryCurrency(categoryID: shown, currencyCode: key.currencyCode), default: 0] += amount
        }
        var reported: [CategoryCurrency: Decimal] = [:]
        for currency in ["INR", "USD"] {
            let report = SpendingReportBuilder.report(
                in: snapshot,
                period: .thisMonth,
                today: R.today,
                currencyCode: currency,
                defaultCurrency: "INR",
            )
            for row in report.rows {
                reported[CategoryCurrency(categoryID: row.categoryID, currencyCode: currency)] = row.amount
            }
        }
        #expect(reported == budgets.filter { $0.value != 0 })
        #expect(reported[CategoryCurrency(categoryID: R.rent.id, currencyCode: "INR")] == 900)
        #expect(reported[CategoryCurrency(categoryID: nil, currencyCode: "INR")] == 700)
        #expect(reported[CategoryCurrency(categoryID: R.electronics.id, currencyCode: "INR")] == 500)
        #expect(reported[CategoryCurrency(categoryID: R.groceries.id, currencyCode: "INR")] == 1_750)
    }
}
