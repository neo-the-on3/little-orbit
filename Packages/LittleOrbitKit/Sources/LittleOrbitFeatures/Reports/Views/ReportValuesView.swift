#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitTheme
    import SwiftUI

    /// Earned, Spent and Left over side by side in a `Grid` (#184 slice 5, UI Designer's spec), each amount on
    /// one line scaling down to half size rather than truncating. At accessibility text sizes they stack, one under
    /// another. Each figure is one VoiceOver element: “Spent, ₹73,748.50”.
    struct ReportValuesView: View {
        let values: [ReportValueModel]
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(values) { cell($0) }
                }
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16) {
                    GridRow {
                        ForEach(values) { cell($0) }
                    }
                }
            }
        }

        private func cell(_ value: ReportValueModel) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(value.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(value.amountText)
                    .font(.title3.bold())
                    .monospacedDigit()
                    .foregroundStyle(value.amountTone.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(value.accessibilityLabel)
        }
    }

    /// The Reports list's This Month summary (#184 slice 5): Spent, Earned and Left over with “Earned − spent,
    /// October 2026 · INR”. With 2 or more currencies its header is the segmented currency picker.
    struct ReportsSummarySection: View {
        let model: ReportsSummaryModel

        var body: some View {
            Section {
                if !model.values.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ReportValuesView(values: model.values)
                        Text(model.caption)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                if model.showsCurrencyPicker {
                    Picker(model.currencyLabel, selection: currency) {
                        ForEach(model.currencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
        }

        private var currency: Binding<String> {
            Binding(get: { model.currencyCode }, set: { code in Task { await model.selectCurrency(code) } })
        }
    }
#endif
