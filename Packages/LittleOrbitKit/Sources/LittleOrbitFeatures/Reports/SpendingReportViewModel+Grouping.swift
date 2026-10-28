import Foundation
import LittleOrbitDomain

/// The wording that differs between the category, payee (#184 slice 4) and income (slice 5) reports. Everything
/// else, from the filters to the drill-down, is shared.
extension SpendingReportViewModel {
    /// Which of the three reports this screen is.
    private enum Kind {
        case categories
        case payees
        case income
    }

    private var kind: Kind {
        if flow == .income {
            return .income
        }
        return grouping == .payee ? .payees : .categories
    }

    /// The report's heading and the audio graph's title: “What do I spend my money on?”, “Where do I spend
    /// the most?” or “Where does my money come from?”.
    public var question: String {
        switch kind {
        case .categories: ReportText.spendingQuestion
        case .payees: ReportText.payeeQuestion
        case .income: ReportText.incomeQuestion
        }
    }

    /// The navigation title, also the Back button's and the Mac window's: “Spending”, “Spending by Payee”
    /// (UI Designer's answer on #314) or “Income”.
    public var navigationTitle: String {
        switch kind {
        case .categories: ReportText.spendingTitle
        case .payees: ReportText.payeeTitle
        case .income: ReportText.incomeTitle
        }
    }

    /// “All Categories”, “All Payees” or “Sources of Income”: the header over the rows.
    public var rowsHeader: String {
        switch kind {
        case .categories: ReportText.allCategories
        case .payees: ReportText.allPayees
        case .income: ReportText.sourcesOfIncome
        }
    }

    /// What the rows count and leave out.
    public var footer: String {
        switch kind {
        case .categories: ReportText.footer
        case .payees: ReportText.payeeFooter
        case .income: ReportText.incomeFooter
        }
    }

    /// The Mac table's first column and the audio graph's category axis: “Category” or “Payee”.
    public var chartCategoryAxis: String {
        kind == .payees ? ReportText.payeeColumn : ReportText.categoryColumn
    }

    /// The empty state's symbol: a cart for spending, a banknote for income.
    public var emptySymbolName: String { kind == .income ? "banknote" : "cart" }

    /// The Other bar's name on the chart and for VoiceOver.
    func otherBarNames(_ count: Int) -> (shown: String, spoken: String) {
        switch kind {
        case .categories: (ReportText.otherCategories(count), ReportText.otherCategoriesSpoken(count))
        case .payees: (ReportText.otherPayees(count), ReportText.otherPayeesSpoken(count))
        case .income: (ReportText.otherSources(count), ReportText.otherSourcesSpoken(count))
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
