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
    /// Income and Expenses, each point read once (`IncomeExpenseAudioGraph`).
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
            series = model.chartAudioSeries
            currencyCode = model.currencyCode
            locale = model.locale
        }

        func makeChartDescriptor() -> AXChartDescriptor {
            IncomeExpenseAudioGraph.descriptor(
                title: title,
                summary: summary,
                monthAxis: monthAxis,
                amountAxis: amountAxis,
                currencyCode: currencyCode,
                locale: locale,
                series: series,
            )
        }
    }
#endif
