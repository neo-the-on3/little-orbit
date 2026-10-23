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
                Text(row.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(row.title)
            }
            .width(min: minWidth, ideal: idealWidth)
        }
    }
#endif
