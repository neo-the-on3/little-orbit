import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// Made-up income for the slice 5 view models (#184).
@MainActor
enum IncomeFixtureFeatures {
    typealias S = SpendingFixture  // swiftlint:disable:this type_name

    static let salary = TransactionCategory(name: "Salary", kind: .income, iconName: "briefcase.fill")
    static let bonus = TransactionCategory(name: "Bonus", kind: .income, parentID: salary.id, iconName: "gift.fill")
    static let interest = TransactionCategory(name: "Interest", kind: .income, iconName: "percent")
    static let sources = ["Gift Shop", "Rentals", "Tutoring", "Resale", "Royalties"]
        .map {
            TransactionCategory(name: $0, kind: .income, iconName: "tag")
        }

    static func income(
        _ amount: String,
        _ category: TransactionCategory?,
        _ month: Int,
        _ day: Int,
        account: Account = S.savings,
        payee: Payee? = nil,
    ) -> Transaction {
        Transaction(
            type: .income,
            amount: Decimal(string: amount)!,
            date: S.date(month, day),
            timeZoneID: S.zone,
            accountID: account.id,
            categoryID: category?.id,
            payeeID: payee?.id,
        )
    }

    static func transfer(_ amount: String, _ month: Int, _ day: Int) -> Transaction {
        Transaction(
            type: .transfer,
            amount: Decimal(string: amount)!,
            date: S.date(month, day),
            timeZoneID: S.zone,
            accountID: S.savings.id,
            transferAccountID: S.usdWallet.id,
        )
    }

    static func snapshot(_ transactions: [Transaction]) -> LedgerSnapshot {
        var snapshot = S.snapshot(transactions)
        snapshot.categories += [salary, bonus, interest] + sources
        return snapshot
    }

    /// October 2026: ₹1,62,000.00 of income, a ₹20,000.00 transfer, a ₹300.00 refund and ₹73,748.50 spent.
    static var october: [Transaction] {
        [
            income("150000", salary, 10, 1, payee: S.payee),
            income("10000", bonus, 10, 5),
            income("2000", interest, 10, 20),
            transfer("20000", 10, 6),
            S.refund("300", S.electronics, 10, 7),
            S.expense("73748.50", S.rent, 10, 2),
        ]
    }
}

@MainActor
@Suite("Sources of income view model (#184 slice 5)")
struct IncomeReportViewModelTests {
    typealias S = SpendingFixture  // swiftlint:disable:this type_name
    typealias I = IncomeFixtureFeatures  // swiftlint:disable:this type_name

    static func model(_ fake: FakeSpendingReportUseCase) -> SpendingReportViewModel {
        SpendingReportViewModel(
            useCase: fake,
            flow: .income,
            locale: S.locale,
            timeZone: TimeZone(identifier: S.zone)!,
            now: { S.date(10, 25) },
        )
    }

    @Test("Given October's fixture, the total is ₹1,62,000.00, with no transfer or refund among the sources (S45, S47)")
    func sources() async throws {
        let fake = FakeSpendingReportUseCase(snapshot: I.snapshot(I.october))
        let model = Self.model(fake)
        await model.load()
        #expect(fake.requests.last?.flow == .income)
        #expect(model.totalText == "₹1,62,000.00")
        #expect(model.totalCaption == "Earned in October 2026 · all accounts · INR")
        #expect(model.rows.map(\.name) == ["Salary", "Salary › Bonus", "Interest"])
        #expect(model.rows.map(\.shareText) == ["92.6%", "6.2%", "1.2%"])
        #expect(model.rows.first?.symbolName == "briefcase.fill")
        let first = try #require(model.rows.first)
        #expect(first.accessibilityLabel.hasPrefix("Salary, ₹1,50,000.00, "))
        #expect(first.accessibilityLabel.hasSuffix(", 92.6%, 1 transaction"))
    }

    @Test("The screen's wording: the question, Income, Sources of Income and the income footer")
    func wording() async {
        let model = Self.model(FakeSpendingReportUseCase(snapshot: I.snapshot([])))
        #expect(model.flow == .income)
        #expect(model.question == "Where does my money come from?")
        #expect(model.chartTitle == "Where does my money come from?")
        #expect(model.navigationTitle == "Income")
        #expect(model.rowsHeader == "Sources of Income")
        #expect(model.footer == "Sorted by amount. Refunds and transfers between your accounts aren’t income.")
        #expect(model.chartCategoryAxis == "Category")
        await model.load()
        #expect(model.isEmpty)
        #expect(model.emptyTitle == "No Income")
        #expect(model.emptyMessage == "There’s no income in this period. Try another period.")
    }

    @Test("The spending report keeps its own wording and its expenses-only rows")
    func spendingUnchanged() async {
        let fake = FakeSpendingReportUseCase(snapshot: I.snapshot(I.october))
        let model = S.model(fake)
        await model.load()
        #expect(model.flow == .spending)
        #expect(model.totalText == "₹73,448.50")
        #expect(model.emptyTitle == "No Expenses")
        #expect(model.totalCaption.hasPrefix("Spent in "))
    }

    @Test("Drilling into Salary lists its income as +amounts, under “92.6% of income”")
    func drillDown() async throws {
        let fake = FakeSpendingReportUseCase(
            snapshot: I.snapshot(I.october + [I.income("500", I.salary, 10, 9)])
        )
        let model = Self.model(fake)
        await model.load()
        let salary = try #require(model.rows.first)
        let drill = try #require(await model.drillDown(for: salary))
        #expect(drill.title == "Salary")
        #expect(drill.amountText == "₹1,50,500.00")
        #expect(drill.caption == "92.6% of income · October 2026 · all accounts · INR")
        #expect(drill.entries.map(\.amountText) == ["+₹500.00", "+₹1,50,000.00"])
        #expect(drill.entries.map(\.amountTone) == [.positive, .positive])
        // With no payee or description, an income reads Income.
        #expect(drill.entries.map(\.title) == ["Income", "Green Basket"])
        #expect(fake.entryRequests.last?.flow == .income)
    }

    @Test("Given 7 sources, the chart has the 5 largest and Other · 2 sources")
    func chartOther() async throws {
        var transactions = [I.income("9000", I.salary, 10, 1), I.income("8000", I.interest, 10, 2)]
        for (index, source) in I.sources.enumerated() {
            transactions.append(I.income("\(7000 - index * 1000)", source, 10, 3 + index))
        }
        let model = Self.model(FakeSpendingReportUseCase(snapshot: I.snapshot(transactions)))
        await model.load()
        let other = try #require(model.chartBars.last)
        #expect(other.name == "Other · 2 sources")
        #expect(other.accessibilityLabel == "Other, 2 sources")
    }

    @Test("D414 on income: with USD income only, the report opens in USD")
    func currency() async {
        let model = Self.model(
            FakeSpendingReportUseCase(
                snapshot: I.snapshot([
                    S.expense("900", S.rent, 10, 2), I.income("1200", I.salary, 10, 1, account: S.usdWallet),
                ])
            )
        )
        await model.load()
        #expect(model.currencyCode == "USD")
        #expect(model.showsCurrencyPicker == false)
    }

    @Test("Reports makes the income report, with its question for the Reports list")
    func feature() {
        let feature = ReportsFeature(
            spendingReport: FakeSpendingReportUseCase(snapshot: S.snapshot([])),
            updates: LedgerUpdates(),
        )
        #expect(feature.incomeQuestion == "Where does my money come from?")
        #expect(feature.makeIncomeReport().flow == .income)
    }
}
