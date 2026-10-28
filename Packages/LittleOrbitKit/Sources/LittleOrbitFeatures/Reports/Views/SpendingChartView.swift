#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import Accessibility
    import Charts
    import LittleOrbitTheme
    import SwiftUI

    /// The ranked bar chart (#184 slice 3, UI Designer's spec): one horizontal bar per category, the 5 largest,
    /// then “Other · n categories” when it combines 2 or more. A bar is its category's colour (Other is secondary),
    /// with a compact amount at its end. There are no gridlines and no x axis. Tapping a bar opens its row's
    /// drill-down; Other isn't tappable.
    ///
    /// VoiceOver (UI Designer's answer on #310): the chart is one element, the report's question with the caption,
    /// and offers the audio graph from `accessibilityChartDescriptor`. The bars are hidden, so VoiceOver never lands
    /// on something it can't act on; the rows below are the way into a drill-down, and stay the full data table
    /// (#185).
    struct SpendingChartView: View {
        let model: SpendingReportViewModel
        let open: (SpendingRowModel) -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        #if os(macOS)
            @ScaledMetric private var barHeight: CGFloat = 44
        #else
            @ScaledMetric private var barHeight: CGFloat = 36
        #endif

        var body: some View {
            Chart(model.chartBars) { bar in
                BarMark(
                    x: .value(model.chartAmountAxis, bar.amount),
                    y: .value(model.chartCategoryAxis, bar.name),
                )
                .foregroundStyle(bar.hue.map { Color($0.token) } ?? Color.secondary)
                .annotation(position: .trailing, alignment: .leading) {
                    // At accessibility sizes the annotations are hidden; the rows below have the amounts.
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(bar.compactAmountText)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityHidden(true)
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let name = value.as(String.self) {
                            Text(name).lineLimit(2)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            tap(at: location, proxy: proxy, geometry: geometry)
                        }
                }
                .accessibilityHidden(true)
            }
            .frame(height: barHeight * CGFloat(model.chartBars.count))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.chartTitle)
            .accessibilityValue(model.chartSummary)
            .accessibilityChartDescriptor(
                SpendingChartDescriptor(
                    title: model.chartTitle,
                    summary: model.chartSummary,
                    categoryAxis: model.chartCategoryAxis,
                    amountAxis: model.chartAmountAxis,
                    currencyCode: model.currencyCode,
                    locale: model.locale,
                    bars: model.chartBars,
                )
            )
        }

        /// Opens the drill-down of the bar at `location`, if it's a category's bar.
        private func tap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
            guard let plot = proxy.plotFrame else {
                return
            }
            let origin = geometry[plot].origin
            guard let name: String = proxy.value(atY: location.y - origin.y), let row = model.chartRow(named: name)
            else {
                return
            }
            open(row)
        }
    }

    /// The audio graph (UI Designer's slice 3 spec): the report title and caption, a categorical Category axis, an
    /// Amount axis read in the shown currency, and one series of the bars.
    struct SpendingChartDescriptor: AXChartDescriptorRepresentable {
        let title: String
        let summary: String
        let categoryAxis: String
        let amountAxis: String
        let currencyCode: String
        let locale: Locale
        let bars: [SpendingChartBar]

        func makeChartDescriptor() -> AXChartDescriptor {
            let code = currencyCode
            let locale = locale
            let largest = bars.map(\.amount).max() ?? 0
            let xAxis = AXCategoricalDataAxisDescriptor(title: categoryAxis, categoryOrder: bars.map(\.name))
            let yAxis = AXNumericDataAxisDescriptor(
                title: amountAxis,
                range: 0...max(largest, 1),
                gridlinePositions: [],
            ) { value in
                Decimal(value).formatted(.currency(code: code).locale(locale))
            }
            let series = AXDataSeriesDescriptor(
                name: title,
                isContinuous: false,
                dataPoints: bars.map { bar in
                    AXDataPoint(x: bar.name, y: bar.amount, additionalValues: [], label: bar.accessibilityValue)
                },
            )
            return AXChartDescriptor(
                title: title,
                summary: summary,
                xAxis: xAxis,
                yAxis: yAxis,
                additionalAxes: [],
                series: [series],
            )
        }
    }
#endif
