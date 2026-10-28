#if canImport(Accessibility)
    import Accessibility
    import Foundation
    import LittleOrbitDomain
    import LittleOrbitFeatures
    import Testing

    /// Income vs expenses' audio graph descriptor (UI Designer's answer 7 on #321): each point once, as its month
    /// and amount. Apple platforms only, where the Accessibility framework is. Made-up data only.
    @MainActor
    @Suite("Income vs expenses audio graph descriptor (#184 slice 5)")
    struct IncomeExpenseAudioGraphTests {
        typealias S = SpendingFixture  // swiftlint:disable:this type_name
        typealias I = IncomeFixtureFeatures  // swiftlint:disable:this type_name

        static func descriptor(_ model: IncomeExpenseReportViewModel) -> AXChartDescriptor {
            IncomeExpenseAudioGraph.descriptor(
                title: model.chartTitle,
                summary: model.chartSummary,
                monthAxis: model.monthColumn,
                amountAxis: model.amountAxis,
                currencyCode: model.currencyCode,
                locale: S.locale,
                series: model.chartAudioSeries,
            )
        }

        @Test("Given October's income and expenses, then each point reads its month and amount once, with no label")
        func pointsReadOnce() async throws {
            let model = IncomeExpenseReportViewModelTests.model(
                FakeSpendingReportUseCase(snapshot: I.snapshot(IncomeExpenseChartTests.transactions))
            )
            await model.load()
            let chart = Self.descriptor(model)
            #expect(chart.series.map(\.name) == ["Income", "Expenses"])
            #expect(chart.series.allSatisfy { $0.dataPoints.count == 6 })
            #expect(chart.series.flatMap(\.dataPoints).allSatisfy { $0.label == nil })
            let xAxis = try #require(chart.xAxis as? AXCategoricalDataAxisDescriptor)
            #expect(xAxis.title == "Month")
            #expect(xAxis.categoryOrder.last == "October 2026")
            #expect(xAxis.categoryOrder.count == 6)
            let yAxis = try #require(chart.yAxis)
            #expect(yAxis.title == "Amount")
            #expect(yAxis.valueDescriptionProvider(162_000) == "₹1,62,000.00")
            #expect(chart.additionalAxes.isEmpty)
            // July's refunds only: the range reaches below 0, so its signed expenses are read.
            #expect(yAxis.range.lowerBound == -300)
            #expect(yAxis.range.upperBound == 162_000)
        }
    }
#endif
