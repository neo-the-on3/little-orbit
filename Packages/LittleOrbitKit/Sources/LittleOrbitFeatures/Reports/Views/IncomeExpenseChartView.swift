#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import Accessibility
    import Charts
    import SwiftUI

    /// Income vs expenses as grouped vertical bars, one pair a month (#184 slice 5, UI Designer's spec). Income is
    /// solid; Expenses is the same colour, lighter. The system legend names both, so colour is never the only cue.
    /// A month with nothing has no bars. VoiceOver reads the chart as one element and offers the audio graph, with
    /// an Income and an Expenses series.
    struct IncomeExpenseChartView: View {
        let model: IncomeExpenseReportViewModel
        @ScaledMetric private var height: CGFloat = 220

        var body: some View {
            Chart(model.chartBars) { bar in
                BarMark(
                    x: .value(model.monthColumn, bar.month, unit: .month),
                    y: .value(model.amountAxis, bar.amount),
                )
                .foregroundStyle(by: .value(model.chartTitle, bar.series))
                .position(by: .value(model.chartTitle, bar.series))
                .accessibilityHidden(true)
            }
            .chartForegroundStyleScale(
                domain: [model.incomeSeries, model.expensesSeries],
                range: [Color.accentColor, Color.accentColor.opacity(0.45)],
            )
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.chartTitle)
            .accessibilityValue(model.chartSummary)
            .accessibilityChartDescriptor(IncomeExpenseChartDescriptor(model: model))
        }
    }

    /// The audio graph: a categorical Month axis, an Amount axis read in the shown currency, and two series,
    /// Income and Expenses.
    struct IncomeExpenseChartDescriptor: AXChartDescriptorRepresentable {
        let title: String
        let summary: String
        let monthAxis: String
        let amountAxis: String
        let series: [(name: String, bars: [IncomeExpenseChartBar])]
        let currencyCode: String
        let locale: Locale

        @MainActor
        init(model: IncomeExpenseReportViewModel) {
            title = model.chartTitle
            summary = model.chartSummary
            monthAxis = model.monthColumn
            amountAxis = model.amountAxis
            series = [model.incomeSeries, model.expensesSeries]
                .map { name in
                    (name, model.chartBars.filter { $0.series == name })
                }
            currencyCode = model.currencyCode
            locale = model.locale
        }

        func makeChartDescriptor() -> AXChartDescriptor {
            let months = series.first?.bars.map(\.monthTitle) ?? []
            let largest = series.flatMap(\.bars).map(\.amount).max() ?? 0
            let code = currencyCode
            let locale = locale
            return AXChartDescriptor(
                title: title,
                summary: summary,
                xAxis: AXCategoricalDataAxisDescriptor(title: monthAxis, categoryOrder: months),
                yAxis: AXNumericDataAxisDescriptor(
                    title: amountAxis,
                    range: 0...max(largest, 1),
                    gridlinePositions: [],
                ) { value in
                    Decimal(value).formatted(.currency(code: code).locale(locale))
                },
                additionalAxes: [],
                series: series.map { name, bars in
                    AXDataSeriesDescriptor(
                        name: name,
                        isContinuous: false,
                        dataPoints: bars.map { bar in
                            AXDataPoint(x: bar.monthTitle, y: bar.amount, additionalValues: [], label: bar.amountText)
                        },
                    )
                },
            )
        }
    }
#endif
