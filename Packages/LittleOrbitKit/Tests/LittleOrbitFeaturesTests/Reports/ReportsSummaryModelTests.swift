import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// The Reports list's This Month summary (#184 slice 5): spent, earned and left over, from the same calculation
/// as income vs expenses. Made-up data only.
@MainActor
@Suite("Reports list period summary (#184 slice 5)")
struct ReportsSummaryModelTests {
    typealias S = SpendingFixture  // swiftlint:disable:this type_name
    typealias I = IncomeFixtureFeatures  // swiftlint:disable:this type_name

    static func model(_ fake: FakeSpendingReportUseCase) -> ReportsSummaryModel {
        ReportsSummaryModel(
            useCase: fake,
            locale: S.locale,
            timeZone: TimeZone(identifier: S.zone)!,
            now: { S.date(10, 25) },
        )
    }

    @Test("Given October's fixture, it shows Spent, Earned and Left over for This Month")
    func values() async {
        let fake = FakeSpendingReportUseCase(snapshot: I.snapshot(I.october))
        let model = Self.model(fake)
        await model.load()
        #expect(model.values.map(\.label) == ["Spent", "Earned", "Left over"])
        #expect(model.values.map(\.amountText) == ["₹73,448.50", "₹1,62,000.00", "+₹88,551.50"])
        #expect(model.values.first?.accessibilityLabel == "Spent, ₹73,448.50")
        #expect(model.caption == "Earned − spent, October 2026 · INR")
        #expect(fake.incomeExpenseRequests.last?.range == .month(year: 2026, month: 10))
        #expect(fake.incomeExpenseRequests.last?.accounts == .all)
    }

    @Test("It agrees with October's row in income vs expenses")
    func agreesWithIncomeExpenses() async throws {
        let fake = FakeSpendingReportUseCase(snapshot: I.snapshot(I.october + [S.expense("10", S.rent, 9, 3)]))
        let summary = Self.model(fake)
        await summary.load()
        let report = IncomeExpenseReportViewModelTests.model(fake)
        await report.load()
        let october = try #require(report.rows.first)
        #expect(october.subtitle == "In \(summary.values[1].amountText) · Out \(summary.values[0].amountText)")
        #expect(october.leftOverText == summary.values[2].amountText)
    }

    @Test("With nothing this month it shows ₹0.00 values in the default currency")
    func nothing() async {
        let model = Self.model(FakeSpendingReportUseCase(snapshot: I.snapshot([I.income("5", I.salary, 9, 1)])))
        await model.load()
        #expect(model.values.map(\.amountText) == ["₹0.00", "₹0.00", "₹0.00"])
        #expect(model.caption == "Earned − spent, October 2026 · INR")
        #expect(!model.showsCurrencyPicker)
    }

    @Test("D420.5: the currency comes from income and spending, and a picked one sticks while Reports is open")
    func currency() async {
        let fake = FakeSpendingReportUseCase(
            snapshot: I.snapshot([I.income("40", I.salary, 10, 2, account: S.usdWallet)])
        )
        let model = Self.model(fake)
        await model.load()
        #expect(model.currencyCode == "USD")
        fake.snapshot = I.snapshot(I.october + [I.income("40", I.salary, 10, 2, account: S.usdWallet)])
        await model.load(at: 1)
        #expect(model.currencies == ["INR", "USD"])
        #expect(model.showsCurrencyPicker)
        await model.selectCurrency("USD")
        await model.load(at: 2)
        #expect(model.currencyCode == "USD")
        #expect(model.values[1].amountText == IncomeExpenseReportViewModelTests.usd40)
        #expect(fake.incomeExpenseRequests.last?.currencyCode == "USD")
    }

    @Test("Hidden accounts and future-dated items this month count (D417)")
    func hiddenAndFuture() async {
        let hidden = Account(name: "Rainy Day", type: .savings, currencyCode: "INR", isHidden: true)
        var snapshot = I.snapshot([I.income("700", I.salary, 10, 30, account: hidden)])
        snapshot.accounts.append(hidden)
        let model = Self.model(FakeSpendingReportUseCase(snapshot: snapshot))
        await model.load()
        #expect(model.values[1].amountText == "₹700.00")
    }

    @Test("A failed read leaves no values rather than wrong ones")
    func failure() async {
        let fake = FakeSpendingReportUseCase(snapshot: I.snapshot(I.october))
        fake.fails = true
        let model = Self.model(fake)
        await model.load()
        #expect(model.values.isEmpty)
        #expect(model.loadFailed)
    }
}
