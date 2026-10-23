#if canImport(SwiftUI) && os(macOS)
    import SwiftUI

    /// The macOS tables' Payee column, built once so every transaction table shows the title the same way
    /// (D234, D235.3): the row title (D233), wide enough for "Refund (original deleted) · Pinewood Pharmacy" at
    /// the default window size, resizable, cut off at the end on one line, with the full title on hover. The
    /// account history uses it; All Transactions, search and the budget detail will too when they're built.
    enum TransactionTitleColumn {
        static let minWidth: CGFloat = 160
        static let idealWidth: CGFloat = 300

        @MainActor
        static func column() -> some TableColumnContent<TransactionRowModel, Never> {
            TableColumn("Payee") { (row: TransactionRowModel) in
                if row.isSplitLine {
                    // A split's line under its row: the line's category, then its note (S45). Each is cut off at
                    // the end with its full text on hover, as the title is (D234.2, D240.3).
                    HStack {
                        Text(row.title)
                            .help(row.title)
                        Text(row.subtitle)
                            .foregroundStyle(.secondary)
                            .help(row.subtitle)
                    }
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityElement(children: .combine)
                } else {
                    Text(row.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(row.title)
                }
            }
            .width(min: minWidth, ideal: idealWidth)
        }
    }
#endif
