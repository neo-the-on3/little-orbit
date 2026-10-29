#if canImport(Accessibility)
    import Accessibility
    import Foundation

    /// The spending chart's audio graph (UI Designer's slice 3 spec): the report title and caption, a categorical
    /// axis of the bars' names, an Amount axis read in the shown currency, and a Share axis.
    ///
    /// Each point has no label of its own, so VoiceOver reads it once, as its name, amount and share: “Travel,
    /// ₹1,23,456.00, 76.6%”. A label repeating the amount and share read them twice (Tester2 on #310).
    public enum SpendingChartAudioGraph {
        public static func descriptor(
            title: String,
            summary: String,
            categoryAxis: String,
            amountAxis: String,
            shareAxis: String,
            currencyCode: String,
            locale: Locale,
            points: [SpendingChartAudioPoint],
        ) -> AXChartDescriptor {
            let largest = points.map(\.amount).max() ?? 0
            let xAxis = AXCategoricalDataAxisDescriptor(title: categoryAxis, categoryOrder: points.map(\.category))
            let yAxis = AXNumericDataAxisDescriptor(
                title: amountAxis,
                range: 0...max(largest, 1),
                gridlinePositions: [],
            ) { value in
                Decimal(value).formatted(.currency(code: currencyCode).locale(locale))
            }
            // Shares only when every point has one; with none, a point reads its name and amount.
            let shares = points.compactMap(\.share)
            let hasShares = !points.isEmpty && shares.count == points.count
            let shareDescriptor = AXNumericDataAxisDescriptor(
                title: shareAxis,
                range: 0...1,
                gridlinePositions: [],
            ) { value in
                Decimal(value).formatted(.percent.precision(.fractionLength(1)).locale(locale))
            }
            let series = AXDataSeriesDescriptor(
                name: title,
                isContinuous: false,
                dataPoints: points.map { point in
                    AXDataPoint(
                        x: point.category,
                        y: point.amount,
                        additionalValues: hasShares ? [.number(point.share ?? 0)] : [],
                        label: nil,
                    )
                },
            )
            return AXChartDescriptor(
                title: title,
                summary: summary,
                xAxis: xAxis,
                yAxis: yAxis,
                additionalAxes: hasShares ? [shareDescriptor] : [],
                series: [series],
            )
        }
    }
#endif
