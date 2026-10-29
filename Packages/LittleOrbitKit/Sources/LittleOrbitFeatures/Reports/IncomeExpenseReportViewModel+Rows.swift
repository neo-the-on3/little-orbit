import Foundation
import LittleOrbitDomain

/// Income vs expenses' figures, rows and bars (#184 slice 5).
extension IncomeExpenseReportViewModel {
    func value(_ label: String, _ amount: Decimal, _ currencyCode: String, signed: Bool = false) -> ReportValueModel {
        let amountText = formatter.string(amount, currencyCode: currencyCode, showsPlus: signed)
        return ReportValueModel(
            label: label,
            amountText: amountText,
            amountTone: signed ? Self.tone(of: amount) : .neutral,
            accessibilityLabel: ReportText.valueSpoken(label, amountText),
        )
    }

    func row(for month: IncomeExpenseMonth, currencyCode: String) -> IncomeExpenseRowModel {
        let start = month.range.start
        return row(
            id: "\(start.year)-\(start.month)",
            title: text.format(start, template: "MMMyyyy"),
            spokenTitle: text.format(start, template: "MMMMyyyy"),
            income: month.income,
            expenses: month.expenses,
            currencyCode: currencyCode,
            isTotal: false,
        )
    }

    func total(of report: IncomeExpenseReport, currencyCode: String) -> IncomeExpenseRowModel {
        row(
            id: "total",
            title: ReportText.totalRow,
            spokenTitle: ReportText.totalRow,
            income: report.income,
            expenses: report.expenses,
            currencyCode: currencyCode,
            isTotal: true,
        )
    }

    func bars(for month: IncomeExpenseMonth, currencyCode: String) -> [IncomeExpenseChartBar] {
        let start = month.range.start
        let date = TransactionCalendar.noon(on: start, timeZoneID: timeZone.identifier) ?? now()
        let monthTitle = text.format(start, template: "MMMMyyyy")
        return [("income", incomeSeries, month.income), ("expenses", expensesSeries, month.expenses)]
            .map { key, series, amount in
                let value = NSDecimalNumber(decimal: amount).doubleValue
                return IncomeExpenseChartBar(
                    id: "\(start.year)-\(start.month)-\(key)",
                    month: date,
                    monthTitle: monthTitle,
                    series: series,
                    isIncome: key == "income",
                    amount: max(0, value),
                    value: value,
                    amountText: formatter.string(amount, currencyCode: currencyCode),
                )
            }
    }

    /// The audio graph's two series, Income then Expenses, each oldest month first. The bars are split by their
    /// series, never by its shown name.
    public var chartAudioSeries: [(name: String, bars: [IncomeExpenseChartBar])] {
        [(incomeSeries, true), (expensesSeries, false)]
            .map { name, isIncome in
                (name, chartBars.filter { $0.isIncome == isIncome })
            }
    }

    /// “₹1,234.00” for an audio graph value, in the shown currency.
    public func chartAmountText(_ amount: Double) -> String {
        formatter.string(Decimal(amount), currencyCode: currencyCode)
    }

    private func row(
        id: String,
        title: String,
        spokenTitle: String,
        income: Decimal,
        expenses: Decimal,
        currencyCode: String,
        isTotal: Bool,
    ) -> IncomeExpenseRowModel {
        let incomeText = formatter.string(income, currencyCode: currencyCode)
        let expensesText = formatter.string(expenses, currencyCode: currencyCode)
        let leftOver = income - expenses
        return IncomeExpenseRowModel(
            id: id,
            title: title,
            incomeText: incomeText,
            expensesText: expensesText,
            leftOverText: formatter.string(leftOver, currencyCode: currencyCode, showsPlus: true),
            leftOverTone: Self.tone(of: leftOver),
            subtitle: ReportText.inOut(income: incomeText, expenses: expensesText),
            accessibilityLabel: ReportText.monthSpoken(
                month: spokenTitle,
                leftOver: formatter.string(leftOver, currencyCode: currencyCode),
                income: incomeText,
                expenses: expensesText,
            ),
            isTotal: isTotal,
        )
    }

    static func tone(of amount: Decimal) -> AmountTone {
        amount > 0 ? .positive : amount < 0 ? .negative : .neutral
    }
}
