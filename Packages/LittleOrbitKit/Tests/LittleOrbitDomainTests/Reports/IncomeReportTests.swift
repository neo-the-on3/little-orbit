import Foundation
import LittleOrbitDomain
import Testing

/// Made-up income for “Where does my money come from?” and income vs expenses (#184 slice 5).
enum IncomeFixture {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias R = ReportFixture  // swiftlint:disable:this type_name

    static let bonus = TransactionCategory(name: "Bonus", kind: .income, parentID: R.salary.id, sortOrder: 7)
    static let interest = TransactionCategory(name: "Interest", kind: .income, sortOrder: 8)

    static func income(
        _ amount: Decimal,
        _ category: TransactionCategory?,
        on date: Date,
        account: UUID = F.savingsID,
    ) -> Transaction {
        var transaction = F.income(amount, on: date, account: account)
        transaction.categoryID = category?.id
        return transaction
    }

    static func snapshot(_ transactions: [Transaction], splits: [TransactionSplit] = []) -> LedgerSnapshot {
        var snapshot = R.snapshot(transactions, splits: splits)
        snapshot.categories += [bonus, interest]
        return snapshot
    }

    static func query(
        _ range: ReportDayRange = .month(year: 2026, month: 10),
        currency: String? = "INR",
        accounts: ReportAccountFilter = .all,
    ) -> SpendingReportQuery {
        SpendingReportQuery(range: range, currencyCode: currency, accounts: accounts, flow: .income)
    }

    /// October 2026: ₹1,50,000.00 salary, a ₹10,000.00 bonus and ₹2,000.00 interest, with a ₹20,000.00 transfer,
    /// a ₹300.00 refund and a ₹73,748.50 expense that are never income.
    static var october: [Transaction] {
        [
            income(150_000, R.salary, on: F.date(2026, 10, 1)),
            income(10_000, bonus, on: F.date(2026, 10, 5)),
            income(2_000, interest, on: F.date(2026, 10, 20)),
            F.transfer(20_000, on: F.date(2026, 10, 6)),
            R.refund(300, R.electronics, on: F.date(2026, 10, 7)),
            R.expense(73_748.50, R.rent, on: F.date(2026, 10, 2)),
        ]
    }
}

/// “Where does my money come from?” (#184 slice 5, UI Designer's spec): income transactions by category.
/// Transfers and refunds are never income (#27, S47).
@Suite("Sources of income (#184 slice 5)")
struct IncomeReportTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias R = ReportFixture  // swiftlint:disable:this type_name
    typealias I = IncomeFixture  // swiftlint:disable:this type_name

    static func report(_ snapshot: LedgerSnapshot, _ query: SpendingReportQuery = I.query()) -> SpendingReport {
        SpendingReportBuilder.report(in: snapshot, query: query, defaultCurrency: "INR")
    }

    @Test("Given October's fixture, the total is ₹1,62,000.00 and a ₹20,000.00 transfer isn't a source (S45, S47)")
    func sources() {
        let report = Self.report(I.snapshot(I.october))
        #expect(report.total == 162_000)
        #expect(report.rows.map(\.categoryID) == [R.salary.id, I.bonus.id, I.interest.id])
        #expect(report.rows.map(\.amount) == [150_000, 10_000, 2_000])
        #expect(report.rows.map(\.shareTenths) == [926, 62, 12])
        // Bonus is its own row under its parent, Salary (D289.1).
        #expect(report.rows[1].parent?.id == R.salary.id)
    }

    @Test("A refund is never income, and an expense isn't either")
    func refundsAreNotIncome() {
        let report = Self.report(I.snapshot([R.refund(300, R.salary, on: F.date(2026, 10, 7))]))
        #expect(report.rows.isEmpty)
        #expect(report.isEmpty)
    }

    @Test("Income with no category is one Uncategorised row, last on a tie")
    func uncategorised() {
        let report = Self.report(
            I.snapshot([
                I.income(500, nil, on: F.date(2026, 10, 3)), I.income(500, I.interest, on: F.date(2026, 10, 4)),
            ])
        )
        #expect(report.rows.map(\.categoryID) == [I.interest.id, nil])
    }

    @Test("D414 on income: the currency comes from income transactions, so USD income opens in USD")
    func currencyFromIncome() {
        let report = Self.report(
            I.snapshot([
                R.expense(900, R.rent, on: F.date(2026, 10, 2)),
                I.income(1_200, R.salary, on: F.date(2026, 10, 1), account: F.usdID),
            ]),
            I.query(currency: nil),
        )
        #expect(report.currencies == ["USD"])
        #expect(report.currencyCode == "USD")
        #expect(report.total == 1_200)
    }

    @Test("Hidden accounts' income counts by default and unticking removes it (D417)")
    func hiddenAccount() {
        var snapshot = I.snapshot([
            I.income(1_000, R.salary, on: F.date(2026, 10, 1)),
            I.income(400, I.interest, on: F.date(2026, 10, 2), account: F.walletID),
        ])
        snapshot.accounts = snapshot.accounts.map { account in
            var copy = account
            copy.isHidden = copy.id == F.walletID
            return copy
        }
        #expect(Self.report(snapshot).total == 1_400)
        #expect(Self.report(snapshot, I.query(accounts: ReportAccountFilter(unticked: [F.walletID]))).total == 1_000)
    }

    @Test("Future-dated income counts in its own period")
    func futureDated() {
        let snapshot = I.snapshot([I.income(5_000, R.salary, on: F.date(2026, 10, 30))])
        #expect(Self.report(snapshot).total == 5_000)
        #expect(Self.report(snapshot, I.query(.month(year: 2026, month: 11))).isEmpty)
    }

    @Test("A split income counts each line in its own category")
    func split() {
        let paid = I.income(12_000, R.salary, on: F.date(2026, 10, 1))
        let lines = [
            TransactionSplit(transactionID: paid.id, categoryID: R.salary.id, amount: 10_000),
            TransactionSplit(transactionID: paid.id, categoryID: I.bonus.id, amount: 2_000),
        ]
        let report = Self.report(I.snapshot([paid], splits: lines))
        #expect(report.rows.map(\.amount) == [10_000, 2_000])
        #expect(report.rows.map(\.transactionCount) == [1, 1])
    }

    @Test("Drilling into Salary lists only its income, with positive amounts that add up to the row")
    func drillDown() {
        let snapshot = I.snapshot(I.october + [I.income(1_000, R.salary, on: F.date(2026, 10, 15))])
        let entries = SpendingReportBuilder.entries(in: snapshot, query: I.query(), rowID: R.salary.id)
        #expect(entries.map(\.amount) == [1_000, 150_000])
        #expect(entries.allSatisfy { $0.transaction.type == .income && !$0.transaction.isRefund })
    }

    @Test("The spending report still counts refunds and not income")
    func spendingUnchanged() {
        let report = SpendingReportBuilder.report(
            in: I.snapshot(I.october),
            query: SpendingReportQuery(range: .month(year: 2026, month: 10), currencyCode: "INR"),
            defaultCurrency: "INR",
        )
        #expect(report.total == 73_448.50)
    }
}
