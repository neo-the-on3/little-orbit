import Foundation
import LittleOrbitDomain
import Testing

/// The ranked bars (#184 slice 3): the 5 largest, then “Other · n categories” only when it combines 2 or more.
@Suite("Spending report chart bars (#184 slice 3)")
struct ReportChartTests {
    static func amounts(_ values: [Int]) -> [Decimal] { values.map { Decimal($0) } }

    static func bars(_ values: [Int]) -> [ReportChartBar] {
        let amounts = amounts(values)
        let total = amounts.reduce(0, +)
        let shares = ReportShares.tenths(of: amounts, total: total) ?? []
        return ReportChart.bars(amounts: amounts, shares: shares)
    }

    @Test("Given 7 categories, then the chart has the 5 largest plus Other · 2 categories, adding up to the total")
    func sevenRows() {
        let bars = Self.bars([700, 600, 500, 400, 300, 200, 100])
        #expect(bars.count == 6)
        #expect(bars.prefix(5).map(\.kind) == (0..<5).map { .row($0) })
        #expect(bars.last?.kind == .other(count: 2))
        #expect(bars.last?.amount == 300)
        #expect(bars.reduce(Decimal(0)) { $0 + $1.amount } == 2_800)
        #expect(bars.compactMap(\.shareTenths).reduce(0, +) == 1_000)
    }

    @Test("Given exactly 6 positive categories, then the 6th gets its own bar, with no Other")
    func sixRows() {
        let bars = Self.bars([600, 500, 400, 300, 200, 100])
        #expect(bars.map(\.kind) == (0..<6).map { .row($0) })
    }

    @Test("Given 5 or fewer categories, then each has a bar and there's no Other")
    func fewRows() {
        #expect(Self.bars([300, 200]).map(\.kind) == [.row(0), .row(1)])
        #expect(Self.bars([]).isEmpty)
    }

    @Test("Zero and refund-only rows get no bar and aren't combined into Other; they stay in the list")
    func negativeRows() {
        let amounts = Self.amounts([700, 600, 500, 400, 300, 200, 0, -150])
        let shares = ReportShares.tenths(of: amounts, total: amounts.reduce(0, +))
        let bars = ReportChart.bars(amounts: amounts, shares: shares ?? [])
        #expect(bars.count == 6)
        // Only 200 is left after the 5 largest, so it gets its own bar rather than an Other of one.
        #expect(bars.last?.kind == .row(5))
        #expect(!bars.contains { $0.amount <= 0 })
        // With a negative row the bars add up to more than the total, as D316's amendment allows.
        #expect(bars.reduce(Decimal(0)) { $0 + $1.amount } == 2_700)
    }

    @Test("Other's share is the sum of the largest-remainder shares it combines")
    func otherShare() throws {
        let amounts = Self.amounts([1, 1, 1, 1, 1, 1, 1])
        let shares = try #require(ReportShares.tenths(of: amounts, total: 7))
        let bars = ReportChart.bars(amounts: amounts, shares: shares)
        #expect(bars.last?.shareTenths == shares[5] + shares[6])
        #expect(bars.compactMap(\.shareTenths).reduce(0, +) == 1_000)
    }

    @Test("Without shares (a total of 0 or below), the bars have no share")
    func noShares() {
        let bars = ReportChart.bars(amounts: Self.amounts([100, 50, 40, 30, 20, 10, 5, -500]), shares: [])
        #expect(bars.allSatisfy { $0.shareTenths == nil })
        #expect(bars.last?.kind == .other(count: 2))
    }
}
