#if canImport(Accessibility)
    import Accessibility
    import Foundation
    import LittleOrbitDomain
    import LittleOrbitFeatures
    import Testing

    /// The audio graph descriptor VoiceOver reads (Tester2 on #310): each point once, as name, amount and share.
    /// Apple platforms only, where the Accessibility framework is. Made-up data only.
    @MainActor
    @Suite("Spending chart audio graph descriptor (#184 slice 3)")
    struct SpendingChartAudioGraphTests {
        typealias S = SpendingFixture  // swiftlint:disable:this type_name

        static func descriptor(_ model: SpendingReportViewModel) -> AXChartDescriptor {
            SpendingChartAudioGraph.descriptor(
                title: model.chartTitle,
                summary: model.chartSummary,
                categoryAxis: model.chartCategoryAxis,
                amountAxis: model.chartAmountAxis,
                shareAxis: model.shareColumn,
                currencyCode: model.currencyCode,
                locale: S.locale,
                points: model.chartAudioPoints,
            )
        }

        @Test(
            "Given Travel and Rent, then each point reads its name, amount and share once, with no label repeating them"
        )
        func pointsReadOnce() async throws {
            let travel = TransactionCategory(name: "Travel", iconName: "airplane")
            var snapshot = S.snapshot([S.expense("123456", travel, 10, 1), S.expense("37744", S.rent, 10, 2)])
            snapshot.categories.append(travel)
            let model = S.model(FakeSpendingReportUseCase(snapshot: snapshot))
            await model.load()
            let chart = Self.descriptor(model)
            let points = try #require(chart.series.first).dataPoints
            #expect(points.count == 2)
            #expect(points.allSatisfy { $0.label == nil })
            let xAxis = try #require(chart.xAxis as? AXCategoricalDataAxisDescriptor)
            #expect(xAxis.categoryOrder == ["Travel", "Rent"])
            // The amount is read once, from the Amount axis; the share once, from the Share axis.
            let yAxis = try #require(chart.yAxis)
            #expect(yAxis.title == "Amount")
            #expect(yAxis.valueDescriptionProvider(123_456) == "₹1,23,456.00")
            #expect(chart.additionalAxes.count == 1)
            let shareAxis = try #require(chart.additionalAxes.first as? AXNumericDataAxisDescriptor)
            #expect(shareAxis.title == "Share")
            let travelPoint = try #require(model.chartAudioPoints.first)
            #expect(shareAxis.valueDescriptionProvider(try #require(travelPoint.share)) == "76.6%")
            #expect(model.rows.first?.shareText == "76.6%")
        }

        @Test(
            "Given a category I named “Uncategorised” and uncategorised spending, then the audio graph has two categories"
        )
        func duplicateNames() async throws {
            let lookalike = TransactionCategory(name: "Uncategorised", iconName: "tag.fill")
            var snapshot = S.snapshot([S.expense("500", lookalike, 10, 1), S.expense("300", nil, 10, 2)])
            snapshot.categories.append(lookalike)
            let model = S.model(FakeSpendingReportUseCase(snapshot: snapshot))
            await model.load()
            let chart = Self.descriptor(model)
            let xAxis = try #require(chart.xAxis as? AXCategoricalDataAxisDescriptor)
            #expect(xAxis.categoryOrder == ["Uncategorised", "Uncategorised (2)"])
            #expect(chart.series.first?.dataPoints.count == 2)
        }
    }
#endif
