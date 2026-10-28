#if canImport(Accessibility)
    import Accessibility
    import Foundation

    /// Income vs expenses' audio graph (UI Designer's slice 5 spec): the report question and caption, a
    /// categorical Month axis, an Amount axis read in the shown currency, and two series, Income and Expenses.
    ///
    /// Each point has no label of its own, so VoiceOver reads it once, as its month and amount: “October 2026,
    /// ₹1,62,000.00”. A label repeating the amount read it twice (as on #310). A month of refunds only reads its
    /// signed expenses, though its bar stays at 0.
    public enum IncomeExpenseAudioGraph {
        public static func descriptor(
            title: String,
            summary: String,
            monthAxis: String,
            amountAxis: String,
            currencyCode: String,
            locale: Locale,
            series: [(name: String, bars: [IncomeExpenseChartBar])],
        ) -> AXChartDescriptor {
            let months = series.first?.bars.map(\.monthTitle) ?? []
            let values = series.flatMap(\.bars).map(\.value)
            let yAxis = AXNumericDataAxisDescriptor(
                title: amountAxis,
                range: min(values.min() ?? 0, 0)...max(values.max() ?? 0, 1),
                gridlinePositions: [],
            ) { value in
                Decimal(value).formatted(.currency(code: currencyCode).locale(locale))
            }
            return AXChartDescriptor(
                title: title,
                summary: summary,
                xAxis: AXCategoricalDataAxisDescriptor(title: monthAxis, categoryOrder: months),
                yAxis: yAxis,
                additionalAxes: [],
                series: series.map { name, bars in
                    AXDataSeriesDescriptor(
                        name: name,
                        isContinuous: false,
                        dataPoints: bars.map { bar in
                            AXDataPoint(x: bar.monthTitle, y: bar.value, additionalValues: [], label: nil)
                        },
                    )
                },
            )
        }
    }
#endif
