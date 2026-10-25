import Foundation
import LittleOrbitDomain
import Observation

/// The iOS budget detail (#25 part 4; detail frames, no-categories frame, edit limit and delete frames). It shows
/// one period at a time, from the first through the current one, with its figures, the transactions that count
/// and the budget's categories. Change Budget Limit and Delete Budget are Undo steps in the window that made them
/// (D307.8). It reads and writes through the budget use cases only.
@MainActor
@Observable
public final class BudgetDetailViewModel {
    public enum State: Equatable, Sendable {
        /// Not loaded yet.
        case loading
        case figures
        /// Every category the budget picked was deleted: D307's empty state with Edit Budget (D307.5).
        case noCategories
        /// The budget was deleted elsewhere (D309).
        case missing
    }

    public let budgetID: UUID
    public private(set) var state: State = .loading
    /// The budget's name, the screen's title.
    public private(set) var name = ""
    public private(set) var header: BudgetDetailHeader?
    /// “Food › Restaurants and Food › Coffee” or “Shopping (incl. Clothes and Electronics)”, in the system list
    /// format.
    public private(set) var categoriesText = ""
    public private(set) var transactions: [BudgetTransactionRow] = []
    /// The sum of the rows, then what updates the budget (S72, D311.6).
    public private(set) var footnote = ""
    public var alert: CategoryAlert?

    /// The new limit as typed in Change Budget Limit, in the device's number format.
    public var limitText = "" {
        didSet { limitEdited = true }
    }
    public internal(set) var limitEdited = false

    @ObservationIgnored let useCases: BudgetDetailUseCases
    @ObservationIgnored let today: @MainActor () -> CalendarDay
    @ObservationIgnored let locale: Locale
    @ObservationIgnored let money: MoneyFormatter
    @ObservationIgnored let dates: BudgetDetailDates
    @ObservationIgnored let history: @MainActor () -> WindowUndoHistory?
    @ObservationIgnored let updates: LedgerUpdates?
    /// The period on show, or `nil` to follow the current one as days pass.
    @ObservationIgnored private var periodIndex: Int?
    @ObservationIgnored private(set) var detail: BudgetDetail?

    init(
        budgetID: UUID,
        useCases: BudgetDetailUseCases,
        today: @escaping @MainActor () -> CalendarDay,
        locale: Locale,
        updates: LedgerUpdates? = nil,
        history: @escaping @MainActor () -> WindowUndoHistory? = { nil },
    ) {
        self.budgetID = budgetID
        self.useCases = useCases
        self.today = today
        self.locale = locale
        self.updates = updates
        self.history = history
        money = MoneyFormatter(locale: locale)
        dates = BudgetDetailDates(locale: locale)
    }

    // MARK: Wording

    public var noCategoriesTitle: String { BudgetText.noCategoriesTitle }
    public var noCategoriesMessage: String { BudgetText.noCategoriesMessage }
    /// The deleted-elsewhere screen's title (D311.7).
    public var missingTitle: String { BudgetText.deletedTitle }
    public var categoriesHeader: String { BudgetText.categoriesSection }
    public var transactionsHeader: String { BudgetText.transactionsSection(transactions.count) }
    public var deleteTitle: String { BudgetText.deleteTitle(name) }
    public var deleteMessage: String { BudgetText.deleteMessage }

    // MARK: Loading

    /// Reads the budget for the period on show. A budget deleted elsewhere shows “This budget no longer exists.”
    /// (D309); any other failure shows “Couldn’t Load Budgets” and keeps what was on show.
    public func load() {
        do {
            let detail = try useCases.detail.detail(of: budgetID, period: periodIndex, today: today())
            apply(detail)
        } catch LedgerValidationError.missingBudget {
            detail = nil
            state = .missing
            header = nil
            transactions = []
        } catch {
            alert = BudgetText.loadFailed
        }
    }

    public func showPreviousPeriod() {
        guard let detail, detail.selected.period.index > 0 else {
            return
        }
        periodIndex = detail.selected.period.index - 1
        load()
    }

    public func showNextPeriod() {
        guard let detail, !detail.isCurrentPeriod else {
            return
        }
        let next = detail.selected.period.index + 1
        periodIndex = next >= detail.currentIndex ? nil : next
        load()
    }

    private func apply(_ detail: BudgetDetail) {
        self.detail = detail
        name = detail.budget.name
        state = detail.hasNoCategories ? .noCategories : .figures
        let names = BudgetDetailNames(detail)
        categoriesText = names.categoriesText
        let lines = detail.lines
        transactions = lines.map { row($0, names: names) }
        header = makeHeader(detail)
        footnote = makeFootnote(lines, currencyCode: detail.budget.currencyCode, categories: names.footnoteCategories)
    }

    // MARK: Header

    private func makeHeader(_ detail: BudgetDetail) -> BudgetDetailHeader {
        let figures = detail.selected.figures
        let status = Self.status(of: detail)
        let period = detail.selected.period
        let isPast = !detail.isCurrentPeriod
        let (headline, subline) = headlines(detail, status: status)
        let timing = timing(detail, status: status)
        let progress: Double? =
            switch status {
            case .notStarted, .noCategories: nil
            case .overspent: 1
            default: Self.progress(of: figures)
            }
        let symbol: String? =
            switch status {
            case .nearLimit: "exclamationmark.triangle.fill"
            case .overspent: "exclamationmark.circle"
            default: nil
            }
        let spentText = BudgetText.spentAmount(money.string(figures.spent, currencyCode: detail.budget.currencyCode))
        var spoken = [dates.range(period), headline]
        if status == .overspent {
            spoken.insert(BudgetText.overspent, at: 1)
        } else if status == .nearLimit {
            spoken.insert(BudgetText.nearLimit, at: 1)
        }
        spoken += [subline]
        if let percent = BudgetRow.percent(of: figures), status != .notStarted {
            spoken.append(BudgetText.percent(percent))
        }
        spoken += [spentText, timing].filter { !$0.isEmpty }
        return BudgetDetailHeader(
            periodText: dates.range(period),
            isCurrentPeriod: detail.isCurrentPeriod,
            canShowPrevious: period.index > 0,
            canShowNext: isPast,
            status: status,
            headline: headline,
            headlineSymbol: symbol,
            subline: subline,
            progress: progress,
            spentText: spentText,
            timingText: timing,
            facts: makeFacts(detail, status: status),
            hints: makeHints(detail, isPast: isPast),
            accessibilityLabel: spoken.joined(separator: ", "),
        )
    }

    /// The large line (left, unused, over or Starts) and the one under it.
    private func headlines(_ detail: BudgetDetail, status: BudgetRow.Status) -> (String, String) {
        let figures = detail.selected.figures
        let code = detail.budget.currencyCode
        let available = money.string(figures.available, currencyCode: code)
        let remaining = money.string(figures.remaining.magnitude, currencyCode: code)
        let ended = BudgetText.ended(
            dates.short.string(detail.selected.period.end, today: today()),
            available: available,
        )
        let isPast = !detail.isCurrentPeriod
        switch status {
        case .notStarted:
            let starts =
                detail.summary.daysUntilNextPeriod == 1
                ? BudgetText.startsTomorrow
                : BudgetText.starts(dates.short.string(detail.budget.startDay, today: today()))
            return (starts, BudgetText.ofAvailable(available))
        case .overspent:
            if figures.available < 0 {
                let spent = money.string(figures.spent, currencyCode: code)
                return (
                    BudgetText.over(remaining),
                    BudgetText.pair(BudgetText.spent(spent), BudgetText.available(available)),
                )
            }
            let limit = BudgetText.overspentLimit(money.string(detail.selected.limit, currencyCode: code))
            return (BudgetText.over(remaining), isPast ? ended : limit)
        case .nothingSpent, .onTrack, .nearLimit, .noCategories:
            if isPast {
                return (BudgetText.unused(remaining), ended)
            }
            let headline = status == .nothingSpent ? BudgetText.nothingSpent : BudgetText.left(remaining)
            return (headline, BudgetText.ofAvailable(available))
        }
    }

    /// The repeat before the start date, nothing on a past period (its subline already says when it ended, D311
    /// amendment), otherwise the days left and the next start.
    private func timing(_ detail: BudgetDetail, status: BudgetRow.Status) -> String {
        if status == .notStarted {
            return BudgetText.recurrence(detail.budget.recurrence)
        }
        if !detail.isCurrentPeriod {
            return ""
        }
        let next = detail.budget.schedule.period(detail.selected.period.index + 1).start
        return BudgetText.pair(
            BudgetText.daysLeft(detail.summary.daysUntilNextPeriod),
            BudgetText.resets(dates.short.string(next, today: today())),
        )
    }

    private func makeFacts(_ detail: BudgetDetail, status: BudgetRow.Status) -> [BudgetDetailHeader.Fact] {
        let isPast = !detail.isCurrentPeriod
        let code = detail.budget.currencyCode
        let selected = detail.selected
        var facts: [BudgetDetailHeader.Fact] = []
        facts.append(
            .init(
                label: isPast ? BudgetText.limitInThisPeriod : BudgetText.limit,
                value: money.string(selected.limit, currencyCode: code),
                tone: .neutral,
            )
        )
        let carriedIn = selected.figures.carriedOver
        if carriedIn != 0, selected.period.index > 0 {
            let previous = detail.budget.schedule.period(selected.period.index - 1)
            facts.append(
                .init(
                    label: BudgetText.carriedFrom(dates.range(previous)),
                    value: money.string(carriedIn, currencyCode: code, showsPlus: true),
                    tone: carriedIn > 0 ? .positive : .negative,
                )
            )
        }
        if isPast, selected.carriedForward != 0 {
            let next = detail.budget.schedule.period(selected.period.index + 1)
            facts.append(
                .init(
                    label: BudgetText.carriedTo(dates.range(next)),
                    value: money.string(selected.carriedForward, currencyCode: code, showsPlus: true),
                    tone: selected.carriedForward > 0 ? .positive : .negative,
                )
            )
        }
        if status == .overspent, !isPast {
            facts.append(
                .init(
                    label: BudgetText.carryOverOverspendingFact,
                    value: detail.budget.carriesOverOverspending ? BudgetText.onValue : BudgetText.offValue,
                    tone: .neutral,
                )
            )
        }
        return facts
    }

    private func makeHints(_ detail: BudgetDetail, isPast: Bool) -> [String] {
        var hints: [String] = []
        let code = detail.budget.currencyCode
        if detail.selected.hasNoAccountInCurrency {
            hints.append(BudgetText.noAccountInCurrency(code))
        } else if let hint = otherCurrencyHint(detail) {
            hints.append(hint)
        }
        if isPast,
            let later = detail.budget.orderedLimits.first(where: {
                $0.startDay > detail.selected.period.start && $0.amount != detail.selected.limit
            })
        {
            hints.append(
                BudgetText.pastLimit(
                    money.string(detail.selected.limit, currencyCode: code),
                    new: money.string(later.amount, currencyCode: code),
                    from: limitStart(later.startDay, recurrence: detail.budget.recurrence),
                )
            )
        }
        return hints
    }

    /// D311.1: the period's other-currency expenses, naming the account when there's one, then the currency that
    /// counts.
    private func otherCurrencyHint(_ detail: BudgetDetail) -> String? {
        let excluded = detail.excludedAccounts
        guard let first = excluded.first else {
            return nil
        }
        let count = excluded.reduce(0) { $0 + $1.transactionCount }
        let accountNames = Dictionary(
            detail.accounts.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first },
        )
        let left =
            excluded.count == 1
            ? BudgetText.otherCurrencyExpenses(
                count,
                account: first.accountID.flatMap { accountNames[$0] } ?? first.currencyCode,
                currency: first.currencyCode,
            )
            : BudgetText.otherCurrencyExpenses(count, accounts: excluded.count)
        return CategoryText.sentences([left, BudgetText.countsOnly(detail.budget.currencyCode)])
    }

    /// D311.3: when a later limit starts. Monthly and yearly budgets name its month (“Oct 2026”); other repeats
    /// name the day (“15 Oct 2026”), since a month could hold more than one of their periods.
    private func limitStart(_ day: CalendarDay, recurrence: BudgetRecurrence) -> String {
        switch recurrence {
        case .monthly, .yearly: dates.month(day)
        case .weekly, .fortnightly, .custom: dates.full(day)
        }
    }

    private static func status(of detail: BudgetDetail) -> BudgetRow.Status {
        if detail.hasNoCategories {
            return .noCategories
        }
        switch detail.selected.state {
        case .notStarted: return .notStarted
        case .overspent: return .overspent
        case .nearLimit: return .nearLimit
        case .onTrack: return detail.selected.figures.netSpending == 0 ? .nothingSpent : .onTrack
        }
    }

    private static func progress(of figures: BudgetFigures) -> Double {
        guard figures.available > 0 else {
            return 0
        }
        let share = Double(truncating: (figures.spent / figures.available) as NSDecimalNumber)
        return min(1, max(0, share))
    }

    // MARK: Rows

    private func row(_ line: BudgetActivityLine, names: BudgetDetailNames) -> BudgetTransactionRow {
        let transaction = line.transaction
        let code = names.currencyCode
        let payee = names.payee(transaction.payeeID)
        let details = TransactionText.trimmed(transaction.details)
        let title: String
        switch line.refund {
        case .notRefund:
            title = payee ?? details ?? BudgetText.expense
        case .linked:
            title = (payee ?? details).map { BudgetText.pair(BudgetText.refund, $0) } ?? BudgetText.refund
        case .originalDeleted:
            title =
                (payee ?? details).map { BudgetText.pair(BudgetText.refundOriginalDeleted, $0) }
                ?? BudgetText.refundOriginalDeleted
        }
        let category = names.categoryName(line.categoryID)
        var parts = [category, names.accountName(transaction.accountID)].compactMap(\.self)
        if line.isSplitLine {
            parts.insert(BudgetText.split, at: 0)
        }
        let subtitle = parts.joined(separator: " · ")
        let amount = money.string(-line.amount, currencyCode: code, showsPlus: true)
        let date = dates.short.string(line.day, today: today())
        return BudgetTransactionRow(
            id: line.id,
            title: title,
            subtitle: subtitle,
            amountText: amount,
            tone: line.amount < 0 ? .positive : line.amount > 0 ? .negative : .neutral,
            dateText: date,
            symbolName: names.symbol(line.categoryID),
            accessibilityLabel: [title, subtitle, amount, date].joined(separator: ", "),
        )
    }

    /// “₹1,000.00 − ₹300.00 + ₹240.00 = ₹940.00”, oldest first, when two or more rows make the total (S72); then
    /// that adding an expense in the budget's categories updates it (D311.6).
    private func makeFootnote(
        _ lines: [BudgetActivityLine],
        currencyCode code: String,
        categories: [String],
    ) -> String {
        let sentence = BudgetText.detailFootnote(BudgetText.alternatives(categories))
        guard lines.count >= 2 else {
            return sentence
        }
        let ordered = Array(lines.reversed())
        var terms = money.string(ordered[0].amount, currencyCode: code)
        for line in ordered.dropFirst() {
            let magnitude = money.string(line.amount.magnitude, currencyCode: code)
            terms += line.amount < 0 ? " \u{2212} \(magnitude)" : " + \(magnitude)"
        }
        let total = money.string(lines.reduce(Decimal(0)) { $0 + $1.amount }, currencyCode: code)
        return CategoryText.sentences([BudgetText.total(terms, total), sentence])
    }
}

/// Names for the detail's categories and rows, from the records the detail use case returned.
struct BudgetDetailNames {
    let currencyCode: String
    private let categories: [UUID: TransactionCategory]
    private let children: [UUID: [TransactionCategory]]
    private let accounts: [UUID: String]
    private let payees: [UUID: String]
    let categoriesText: String
    /// The picked categories' own names, in order, for the footnote (D311.6).
    let footnoteCategories: [String]

    init(_ detail: BudgetDetail) {
        currencyCode = detail.budget.currencyCode
        let byID = Dictionary(detail.categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        categories = byID
        let ordered = detail.categories.sorted { lhs, rhs in
            lhs.sortOrder != rhs.sortOrder
                ? lhs.sortOrder < rhs.sortOrder : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        children = Dictionary(grouping: ordered.filter { $0.parentID != nil }) { $0.parentID ?? UUID() }
        accounts = Dictionary(detail.accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        payees = Dictionary(detail.payees.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let picked = Set(detail.budget.categoryIDs)
        let children = children
        let pickedCategories = ordered.filter { picked.contains($0.id) }
        footnoteCategories = pickedCategories.map(\.name)
        let texts =
            pickedCategories
            .map { category in
                if let parentID = category.parentID, let parent = byID[parentID] {
                    return BudgetText.path(parent.name, category.name)
                }
                let subcategories = children[category.id] ?? []
                guard !subcategories.isEmpty else {
                    return category.name
                }
                return BudgetText.including(category.name, CategoryText.list(subcategories.map(\.name)))
            }
        categoriesText = CategoryText.list(texts)
    }

    func categoryName(_ id: UUID?) -> String? {
        id.flatMap { categories[$0]?.name }
    }

    func accountName(_ id: UUID?) -> String? {
        id.flatMap { accounts[$0] }
    }

    func payee(_ id: UUID?) -> String? {
        id.flatMap { payees[$0] }
    }

    func symbol(_ id: UUID?) -> String {
        guard let category = id.flatMap({ categories[$0] }) else {
            return "questionmark"
        }
        return category.iconName ?? category.parentID.flatMap { categories[$0]?.iconName } ?? "questionmark"
    }
}
