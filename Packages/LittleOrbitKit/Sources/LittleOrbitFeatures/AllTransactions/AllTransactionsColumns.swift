/// The Mac All Transactions table's columns, in their fixed 1.0 order (D421.3, D425.2). Amount is always last.
enum AllTransactionsColumn: CaseIterable, Sendable {
    case date, description, payee, category, account, amount
}

/// One column's width in points, for `TableColumn.width(min:ideal:max:)`. A nil `max` lets the column grow.
struct AllTransactionsColumnWidth: Equatable, Sendable {
    let min: Double
    let ideal: Double
    let max: Double?
}

/// Column widths for the Mac All Transactions table (D-ruling 6486981842). On a fresh launch at the default
/// 1200 × 760 window, every column fits the 920 pt scroll area with no horizontal scroll bar. The table keeps
/// no saved column state, so the first layout always uses these ideals.
///
/// One column is flexible and takes whatever space is left: Description by default. Every other column has
/// one fixed width, so wider windows give the extra space only to the flexible column. To let Payee flex
/// instead, change `flexible` in `standard` to `.payee`.
///
/// Arithmetic at the default window:
/// - fixed: Date 90 + Payee 130 + Category 120 + Account 130 + Amount 120 = 590
/// - chrome: 6 columns × 17 pt intercell spacing + 2 × 10 pt inset = 122 (the 4d9ec1b table measured 117 pt
///   over its ideals: 1027 content − 910 ideals)
/// - Description: 920 − 590 − 122 = 208 ≥ 160; at its 200 pt ideal the content is 912 ≤ 920.
enum AllTransactionsColumnSpec {
    struct Layout: Sendable {
        let flexible: AllTransactionsColumn

        func width(for column: AllTransactionsColumn) -> AllTransactionsColumnWidth {
            if column == flexible {
                return AllTransactionsColumnWidth(min: 160, ideal: 200, max: nil)
            }
            switch column {
            case .date: return Self.fixed(90)
            case .description, .payee, .account: return Self.fixed(130)
            case .category: return Self.fixed(120)
            case .amount: return AllTransactionsColumnWidth(min: 110, ideal: 120, max: 120)
            }
        }

        /// The fixed columns' ideal widths, without spacing.
        var fixedIdealWidth: Double {
            AllTransactionsColumn.allCases.filter { $0 != flexible }.reduce(0) { $0 + width(for: $1).ideal }
        }

        /// Every column at its ideal width, plus the table's spacing and insets.
        var idealContentWidth: Double {
            fixedIdealWidth + width(for: flexible).ideal + AllTransactionsColumnSpec.chromeWidth
        }

        /// The space the flexible column gets in a scroll area of `scrollWidth` points.
        func flexibleWidth(in scrollWidth: Double) -> Double {
            scrollWidth - fixedIdealWidth - AllTransactionsColumnSpec.chromeWidth
        }

        /// The narrowest scroll area that shows every column with no horizontal scroll bar.
        var narrowestFit: Double {
            fixedIdealWidth + width(for: flexible).min + AllTransactionsColumnSpec.chromeWidth
        }

        private static func fixed(_ points: Double) -> AllTransactionsColumnWidth {
            AllTransactionsColumnWidth(min: points, ideal: points, max: points)
        }
    }

    /// The layout the table uses.
    static let standard = Layout(flexible: .description)

    /// The table's scroll area in the default 1200 × 760 window, beside the sidebar.
    static let defaultScrollWidth = 920.0
    /// The inset table style's intercell spacing per column.
    static let intercellSpacing = 17.0
    /// The inset table style's leading plus trailing content inset.
    static let horizontalInsets = 20.0
    static var chromeWidth: Double {
        Double(AllTransactionsColumn.allCases.count) * intercellSpacing + horizontalInsets
    }

    static var flexible: AllTransactionsColumn { standard.flexible }
    static func width(for column: AllTransactionsColumn) -> AllTransactionsColumnWidth {
        standard.width(for: column)
    }
    static var fixedIdealWidth: Double { standard.fixedIdealWidth }
    static var idealContentWidth: Double { standard.idealContentWidth }
    static func flexibleWidth(in scrollWidth: Double) -> Double { standard.flexibleWidth(in: scrollWidth) }
    static var narrowestFit: Double { standard.narrowestFit }
}
