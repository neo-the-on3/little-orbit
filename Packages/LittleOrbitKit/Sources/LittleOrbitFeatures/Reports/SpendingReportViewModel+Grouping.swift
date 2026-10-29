import Foundation
import LittleOrbitDomain

/// The wording that differs between the category report and the payee report (#184 slice 4). Everything else,
/// from the filters to the drill-down, is shared.
extension SpendingReportViewModel {
    /// The report's heading and the audio graph's title: “What do I spend my money on?” or “Where do I spend
    /// the most?”.
    public var question: String {
        switch grouping {
        case .category: ReportText.spendingQuestion
        case .payee: ReportText.payeeQuestion
        }
    }

    /// The navigation title, also the Back button's and the Mac window's: “Spending”, or “Spending by Payee”
    /// (UI Designer's answer on #314).
    public var navigationTitle: String {
        switch grouping {
        case .category: ReportText.spendingTitle
        case .payee: ReportText.payeeTitle
        }
    }

    /// “All Categories” or “All Payees”: the header over the rows.
    public var rowsHeader: String {
        switch grouping {
        case .category: ReportText.allCategories
        case .payee: ReportText.allPayees
        }
    }

    /// What the rows count and leave out.
    public var footer: String {
        switch grouping {
        case .category: ReportText.footer
        case .payee: ReportText.payeeFooter
        }
    }

    /// The Mac table's first column and the audio graph's category axis: “Category” or “Payee”.
    public var chartCategoryAxis: String {
        switch grouping {
        case .category: ReportText.categoryColumn
        case .payee: ReportText.payeeColumn
        }
    }

    /// The Other bar's name on the chart and for VoiceOver.
    func otherBarNames(_ count: Int) -> (shown: String, spoken: String) {
        switch grouping {
        case .category: (ReportText.otherCategories(count), ReportText.otherCategoriesSpoken(count))
        case .payee: (ReportText.otherPayees(count), ReportText.otherPayeesSpoken(count))
        }
    }

    /// A row's name: “Rent”, “Food & Dining › Groceries” or “Uncategorised”; or “Sunrise Apartments” or
    /// “No Payee”.
    func name(of row: SpendingReportRow) -> String {
        if grouping == .payee {
            return row.payee?.name ?? ReportText.noPayee
        }
        guard let category = row.category else {
            return ReportText.uncategorised
        }
        guard let parent = row.parent else {
            return category.name
        }
        return ReportText.subcategoryName(category.name, parent: parent.name)
    }
}
