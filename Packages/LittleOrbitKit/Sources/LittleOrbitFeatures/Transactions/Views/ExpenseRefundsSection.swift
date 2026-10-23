#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import LittleOrbitTheme
    import SwiftUI

    /// Edit Expense's Refunds section (D117.5, S61): one row per refund, "Refund" with its day, and the amount
    /// with the account it went to, with the refunds footnote under the list (D222.2). Left out when the expense
    /// has no refunds.
    struct ExpenseRefundsSection: View {
        let rows: [ExpenseRefundRow]
        let footnote: String?
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            if !rows.isEmpty {
                Section {
                    ForEach(rows) { row in
                        refundRow(row)
                            .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Refunds")
                } footer: {
                    if let footnote {
                        Text(footnote)
                    }
                }
            }
        }

        /// The day on the left and the amount and account on the right; stacked at accessibility sizes, as the
        /// transaction rows are, with the signed amount kept as one unit on one line.
        @ViewBuilder
        private func refundRow(_ row: ExpenseRefundRow) -> some View {
            let amount = Text(row.amount)
                .foregroundStyle(Color(ThemeColor.moneyPositive))
                .monospacedDigit()
                .lineLimit(1)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.spaceHalf) {
                    Text("Refund")
                    Text(row.date)
                        .foregroundStyle(.secondary)
                    amount
                        .minimumScaleFactor(0.5)
                    Text(row.account)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LabeledContent {
                    VStack(alignment: .trailing) {
                        amount
                            .fixedSize()
                            .layoutPriority(1)
                        Text(row.account)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Refund")
                    Text(row.date)
                }
            }
        }
    }
#endif
