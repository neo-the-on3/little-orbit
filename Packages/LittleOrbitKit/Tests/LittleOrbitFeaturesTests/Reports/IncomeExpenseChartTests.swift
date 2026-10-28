import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// Income vs expenses' bars and audio graph series (#184 slice 5, UI Designer's answer 7). Made-up data only.
@MainActor
@Suite("Income vs expenses chart bars (#184 slice 5)")
struct IncomeExpenseChartTests {
    typealias S = SpendingFixture  // swiftlint:disable:this type_name
    typealias I = IncomeFixtureFeatures  // swiftlint:disable:this type_name
    typealias M = IncomeExpenseReportViewModelTests  // swiftlint:disable:this type_name

    /// October's fixture, plus a July of refunds only: ₹300.00 back on rent.
    static var transactions: [Transaction] {
        I.october + [S.refund("300", S.rent, 7, 5)]
    }

    @Test("Each bar is keyed by its month and series, never by a shown name")
    func barIDs() async throws {
        let model = M.model(FakeSpendingReportUseCase(snapshot: I.snapshot(Self.transactions)))
        await model.load()
        #expect(Set(model.chartBars.map(\.id)).count == model.chartBars.count)
        let october = model.chartBars.filter { $0.monthTitle == "October 2026" }
        #expect(october.map(\.id) == ["2026-10-income", "2026-10-expenses"])
        #expect(october.map(\.isIncome) == [true, false])
    }

    @Test(
        "Given a July of refunds only, when the chart shows, then its Expenses bar is at 0 and the audio graph reads −₹300.00"
    )
    func refundOnlyMonth() async throws {
        let model = M.model(FakeSpendingReportUseCase(snapshot: I.snapshot(Self.transactions)))
        await model.load()
        let july = try #require(model.chartBars.first { $0.monthTitle == "July 2026" && !$0.isIncome })
        #expect(july.amount == 0)
        #expect(july.value == -300)
        #expect(july.amountText.hasSuffix("300.00"))
        #expect(july.amountText != "₹300.00")
    }

    @Test("The audio graph has an Income and an Expenses series, one point a month each, oldest first")
    func audioSeries() async {
        let model = M.model(FakeSpendingReportUseCase(snapshot: I.snapshot(Self.transactions)))
        await model.load()
        let series = model.chartAudioSeries
        #expect(series.map(\.name) == ["Income", "Expenses"])
        #expect(series.allSatisfy { $0.bars.count == 6 })
        #expect(series[0].bars.allSatisfy { $0.isIncome })
        #expect(series[1].bars.allSatisfy { !$0.isIncome })
        #expect(series[0].bars.map(\.monthTitle) == series[1].bars.map(\.monthTitle))
        #expect(series[0].bars.last?.monthTitle == "October 2026")
        #expect(series[0].bars.last?.value == 162_000)
    }
}
