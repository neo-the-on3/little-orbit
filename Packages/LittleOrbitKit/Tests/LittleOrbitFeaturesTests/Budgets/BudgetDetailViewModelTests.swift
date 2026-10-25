import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// The iOS budget detail (#25 part 4): the header states from the detail frames, D307.2 and D308, carry-over and
/// past periods, the other-currency hint (D307.3), the categories, the transaction rows (D233, D237, S72–S75),
/// the no-categories empty state (D307.5) and a budget deleted elsewhere (D309). Today is 20 Oct 2026.
@MainActor
@Suite("Budget detail (#25)")
struct BudgetDetailViewModelTests {
    typealias T = TransactionFeatureFixture  // swiftlint:disable:this type_name
    typealias B = BudgetFeatureFixture  // swiftlint:disable:this type_name

    static func feature(_ repository: InMemoryLedgerRepository, updates: LedgerUpdates? = nil) -> BudgetsFeature {
        let budgets = DefaultBudgetUseCases(repository: repository, now: { T.now })
        return BudgetsFeature(
            useCases: BudgetScreenUseCases(
                list: budgets,
                detail: BudgetDetailUseCases(detail: budgets, changes: budgets),
            ),
            updates: updates,
            locale: T.india,
            today: { T.today },
        )
    }

    private func detail(
        _ budget: Budget,
        _ transactions: [Transaction] = [],
        repository: InMemoryLedgerRepository? = nil,
    ) throws -> BudgetDetailViewModel {
        let repository = try repository ?? B.repository([budget], transactions)
        let model = try #require(Self.feature(repository).makeDetail(budget.id))
        model.load()
        return model
    }

    /// A period range as the platform formats it for the tests' locale, so the expectations follow ICU's spacing
    /// and dashes on Linux and macOS alike (#177 review NB1).
    static func range(_ start: CalendarDay, _ end: CalendarDay) -> String {
        let formatter = DateIntervalFormatter()
        formatter.locale = T.india
        formatter.calendar = BudgetDays.calendar
        formatter.timeZone = BudgetDays.calendar.timeZone
        formatter.dateTemplate = "dMMMy"
        return formatter.string(from: BudgetDays.date(start), to: BudgetDays.date(end))
    }

    static var september: String {
        range(CalendarDay(year: 2026, month: 9, day: 1), CalendarDay(year: 2026, month: 9, day: 30))
    }

    static var october: String {
        range(CalendarDay(year: 2026, month: 10, day: 1), CalendarDay(year: 2026, month: 10, day: 31))
    }

    private func fact(_ model: BudgetDetailViewModel, _ label: String) -> String? {
        model.header?.facts.first { $0.label == label }?.value
    }

    @Test("Frame: detail on track: left, of available, the bar, spent and the days to the next period")
    func onTrack() throws {
        let model = try detail(B.budget("Eating out", limit: 9_500), [B.expense(3_450, day: 12)])
        let header = try #require(model.header)
        #expect(model.state == .figures)
        #expect(model.name == "Eating out")
        #expect(header.periodText == Self.october)
        #expect(header.headline == "₹6,050.00 left")
        #expect(header.subline == "of ₹9,500.00 available")
        #expect(header.spentText == "Spent ₹3,450.00")
        #expect(header.timingText == "12 days left · resets 1 Nov")
        #expect(header.progress.map { abs($0 - 3_450 / 9_500) < 0.0001 } == true)
        #expect(header.canShowPrevious == false)
        #expect(header.canShowNext == false)
        #expect(fact(model, "Limit") == "₹9,500.00")
        #expect(header.hints.isEmpty)
    }

    @Test("Near limit: the warning symbol and the share in VoiceOver")
    func nearLimit() throws {
        let model = try detail(B.budget("Groceries", limit: 12_000), [B.expense(11_250)])
        let header = try #require(model.header)
        #expect(header.status == .nearLimit)
        #expect(header.headlineSymbol == "exclamationmark.triangle.fill")
        #expect(header.accessibilityLabel.contains("Near limit, ₹750.00 left"))
        #expect(header.accessibilityLabel.contains("94%"))
    }

    @Test("Frame: detail overspent: over, full bar, the limit, and whether overspending carries over")
    func overspent() throws {
        let model = try detail(B.budget("Shopping", limit: 5_000), [B.expense(6_200)])
        let header = try #require(model.header)
        #expect(header.status == .overspent)
        #expect(header.headline == "₹1,200.00 over")
        #expect(header.headlineSymbol == "exclamationmark.circle")
        #expect(header.subline == "Overspent · limit ₹5,000.00")
        #expect(header.progress == 1)
        #expect(fact(model, "Carry over overspending") == "Off")
    }

    @Test("D307.2: below 0 available with nothing spent is overspent, with spent and available named")
    func belowZero() throws {
        let budget = B.budget(
            "Shopping",
            limit: 5_000,
            from: CalendarDay(year: 2026, month: 9, day: 1),
            carriesOverOverspending: true,
        )
        let model = try detail(budget, [B.expense(10_500, month: 9, day: 10)])
        let header = try #require(model.header)
        #expect(header.headline == "₹500.00 over")
        #expect(header.subline == "₹0.00 spent · −₹500.00 available")
        #expect(header.progress == 1)
        #expect(fact(model, "Carried over from \(Self.september)") == "−₹5,500.00")
        #expect(fact(model, "Carry over overspending") == "On")
    }

    @Test("Frame: previous period, with carry-over: unused, ended, the old limit kept and the hint")
    func pastPeriod() throws {
        var budget = B.budget("Eating out", limit: 7_000, from: CalendarDay(year: 2026, month: 9, day: 1))
        budget.carriesOverUnspent = true
        budget.limits.append(BudgetLimit(startDay: CalendarDay(year: 2026, month: 10, day: 1), amount: 8_000))
        let model = try detail(budget, [B.expense(5_500, month: 9, day: 6), B.expense(3_450, day: 12)])
        #expect(model.header?.headline == "₹6,050.00 left")
        #expect(model.header?.subline == "of ₹9,500.00 available")
        #expect(fact(model, "Carried over from \(Self.september)") == "+₹1,500.00")
        #expect(model.header?.facts.first { $0.label.hasPrefix("Carried") }?.tone == .positive)
        #expect(model.header?.canShowPrevious == true)

        model.showPreviousPeriod()
        let header = try #require(model.header)
        #expect(header.periodText == Self.september)
        #expect(header.isCurrentPeriod == false)
        #expect(header.headline == "₹1,500.00 unused")
        #expect(header.subline == "Ended 30 Sep · of ₹7,000.00")
        #expect(header.timingText.isEmpty, "D311 amendment: the subline already says Ended")
        #expect(!header.accessibilityLabel.hasSuffix(", "))
        #expect(fact(model, "Limit in this period") == "₹7,000.00")
        #expect(fact(model, "Carried over to \(Self.october)") == "+₹1,500.00")
        #expect(
            header.hints == [
                "The limit was ₹7,000.00 in this period. The change to ₹8,000.00 applies from Oct 2026 onwards."
            ]
        )
        #expect(header.canShowNext)
        #expect(header.canShowPrevious == false)

        model.showNextPeriod()
        #expect(model.header?.periodText == Self.october)
        #expect(model.header?.canShowNext == false)
    }

    @Test("D311.3: a weekly budget's past-limit hint names the day the change starts")
    func pastLimitWeekly() throws {
        var budget = B.budget(
            "Coffee",
            limit: 700,
            from: CalendarDay(year: 2026, month: 10, day: 5),
            recurrence: .weekly,
        )
        budget.limits.append(BudgetLimit(startDay: CalendarDay(year: 2026, month: 10, day: 12), amount: 800))
        let model = try detail(budget)
        model.showPreviousPeriod()
        model.showPreviousPeriod()
        #expect(
            model.header?.periodText
                == Self.range(
                    CalendarDay(year: 2026, month: 10, day: 5),
                    CalendarDay(year: 2026, month: 10, day: 11),
                )
        )
        #expect(
            model.header?.hints == [
                "The limit was ₹700.00 in this period. The change to ₹800.00 applies from 12 Oct 2026 onwards."
            ]
        )
    }

    @Test("D308 amendment: before the start date, “Starts tomorrow” or “Starts 1 Nov”, no bar, just the repeat")
    func notStarted() throws {
        let tomorrow = try detail(
            B.budget("Holidays", limit: 50_000, from: CalendarDay(year: 2026, month: 10, day: 21))
        )
        #expect(tomorrow.header?.headline == "Starts tomorrow")
        #expect(tomorrow.header?.progress == nil)
        #expect(tomorrow.header?.timingText == "Monthly")
        #expect(tomorrow.header?.subline == "of ₹50,000.00 available")
        let later = try detail(
            B.budget("Holidays", limit: 50_000, from: CalendarDay(year: 2026, month: 11, day: 1), recurrence: .yearly)
        )
        #expect(later.header?.headline == "Starts 1 Nov")
        #expect(later.header?.timingText == "Yearly")
    }

    @Test("D308.3: “Last day” on the period's last day")
    func lastDay() throws {
        let model = try detail(B.budget("Eating out", limit: 1_000, from: CalendarDay(year: 2026, month: 9, day: 21)))
        #expect(model.header?.timingText == "Last day · resets 21 Oct")
    }

    @Test("D307.5: a budget with no categories left shows the No Categories empty state")
    func noCategories() throws {
        let budget = B.budget("Monthly food", limit: 1_000, categories: [B.shoppingID])
        let repository = try B.repository([budget])
        try repository.deleteCategory(id: B.shoppingID, reassigningTo: nil)
        let model = try detail(budget, repository: repository)
        #expect(model.state == .noCategories)
        #expect(model.noCategoriesTitle == "No Categories")
        #expect(model.noCategoriesMessage == "Pick at least one category to track spending.")
    }

    @Test("D309: a budget deleted elsewhere says it no longer exists")
    func missing() throws {
        let repository = try B.repository()
        let model = try #require(Self.feature(repository).makeDetail(UUID()))
        model.load()
        #expect(model.state == .missing)
        #expect(model.missingTitle == "This budget no longer exists.")
    }

    @Test("D311.1, D307.3, S5, S7: the other-currency hint counts and names the account, and the no-account hint")
    func currencyHint() throws {
        let dollars = T.expense(20, on: T.date(2026, 10, 5), account: T.usdID, category: B.eatingOutID)
        let model = try detail(B.budget("Eating out", limit: 9_500), [dollars])
        #expect(
            model.header?.hints == [
                "1 expense from USD Wallet (USD) isn’t included. This budget counts INR accounts only."
            ]
        )
        let lastMonth = T.expense(9, on: T.date(2026, 9, 25), account: T.usdID, category: B.eatingOutID)
        let more = T.expense(30, on: T.date(2026, 10, 6), account: T.usdID, category: B.eatingOutID)
        let two = try detail(B.budget("Eating out", limit: 9_500), [dollars, more, lastMonth])
        #expect(
            two.header?.hints == [
                "2 expenses from USD Wallet (USD) aren’t included. This budget counts INR accounts only."
            ],
            "Counts are for the period on show",
        )
        let euroAccount = Account(name: "Euro Pocket", type: .cash, currencyCode: "EUR")
        let repository = try B.repository()
        try repository.saveAccount(euroAccount)
        let budget = B.budget("Eating out", limit: 9_500)
        try repository.saveBudget(budget)
        for transaction in [
            dollars, more, T.expense(12, on: T.date(2026, 10, 7), account: euroAccount.id, category: B.eatingOutID),
        ] {
            try repository.saveTransaction(transaction)
        }
        #expect(
            try detail(budget, repository: repository).header?.hints == [
                "3 expenses from 2 accounts in other currencies aren’t included. This budget counts INR accounts only."
            ]
        )
        let euros = try detail(B.budget("Trip", limit: 500, currency: "EUR"))
        #expect(
            euros.header?.hints == [
                "You have no EUR account, so nothing counts yet. This budget counts EUR accounts only."
            ]
        )
    }

    @Test("Categories: a picked parent lists its subcategories; a picked subcategory shows its parent")
    func categories() throws {
        let clothes = TransactionCategory(name: "Clothes", kind: .expense, parentID: B.shoppingID, sortOrder: 1)
        let repository = try B.repository()
        try repository.saveCategory(clothes)
        let shoes = TransactionCategory(name: "Shoes", kind: .expense, parentID: B.shoppingID, sortOrder: 2)
        try repository.saveCategory(shoes)
        let parent = B.budget("Shopping", limit: 5_000, categories: [B.shoppingID])
        let child = B.budget("Clothes", limit: 2_000, categories: [clothes.id, B.eatingOutID])
        try repository.saveBudget(parent)
        try repository.saveBudget(child)
        // #177 review NB2: the system list format, not a hardcoded “, ”.
        #expect(
            try detail(parent, repository: repository).categoriesText
                == "Shopping trips (incl. \(CategoryText.list(["Clothes", "Shoes"])))"
        )
        #expect(
            try detail(child, repository: repository).categoriesText
                == CategoryText.list(["Shopping trips › Clothes", "Eating out"])
        )
    }

    @Test("S72–S75: payee titles, refund titles and +amounts, the split marker, newest first, and the sum")
    func transactionRows() throws {
        let repository = try B.repository()
        let payee = Payee(name: "Trailhead Sports")
        try repository.savePayee(payee)
        let expense = T.expense(1_000, on: T.date(2026, 10, 3), category: B.shoppingID, payee: payee.id)
        var refund = T.income(300, on: T.date(2026, 10, 8), category: B.shoppingID)
        refund.isRefund = true
        refund.refundOfID = expense.id
        refund.payeeID = payee.id
        var noPayee = T.income(50, on: T.date(2026, 10, 9), category: B.shoppingID)
        noPayee.isRefund = true
        noPayee.details = "R1 Trailhead refund"
        let split = T.expense(1_240, on: T.date(2026, 10, 12), payee: nil, details: "Green Basket")
        for transaction in [expense, refund, noPayee, split] {
            try repository.saveTransaction(transaction)
        }
        try repository.replaceSplits(
            [
                TransactionSplit(transactionID: split.id, categoryID: B.eatingOutID, amount: 240),
                TransactionSplit(transactionID: split.id, categoryID: nil, amount: 1_000, sortOrder: 1),
            ],
            for: split.id,
        )
        let budget = B.budget("Shopping", limit: 5_000, categories: [B.shoppingID, B.eatingOutID])
        try repository.saveBudget(budget)
        let model = try detail(budget, repository: repository)
        #expect(model.header?.headline == "₹4,110.00 left")
        #expect(
            model.transactions.map(\.title) == [
                "Green Basket", "Refund (original deleted) · R1 Trailhead refund", "Refund · Trailhead Sports",
                "Trailhead Sports",
            ]
        )
        #expect(model.transactions[0].subtitle == "Split · Eating out · Everyday Savings")
        #expect(model.transactions[0].amountText == "−₹240.00")
        #expect(model.transactions[0].tone == .negative)
        #expect(model.transactions[2].subtitle == "Shopping trips · Everyday Savings")
        #expect(model.transactions[2].amountText == "+₹300.00")
        #expect(model.transactions[2].tone == .positive)
        #expect(model.transactions[3].dateText == "3 Oct")
        #expect(model.transactions[2].accessibilityLabel.hasPrefix("Refund · Trailhead Sports, "))
        #expect(model.transactionsHeader == "Transactions · 4")
        #expect(
            model.footnote
                == "₹1,000.00 − ₹300.00 − ₹50.00 + ₹240.00 = ₹890.00 Adding an expense in "
                + BudgetText.alternatives(["Eating out", "Shopping trips"])
                + " updates this budget straight away. Transfers never count."
        )
    }

    @Test("D311.6, D311.9: with one row only the sentence; untitled rows read “Expense” and “Refund”")
    func footnoteAndFallbackTitles() throws {
        let repository = try B.repository()
        let expense = T.expense(400, on: T.date(2026, 10, 3), category: B.eatingOutID)
        let budget = B.budget("Eating out", limit: 5_000)
        try repository.saveTransaction(expense)
        try repository.saveBudget(budget)
        let one = try detail(budget, repository: repository)
        #expect(one.transactions.map(\.title) == ["Expense"])
        #expect(
            one.footnote == "Adding an expense in Eating out updates this budget straight away. Transfers never count."
        )
        var refund = T.income(100, on: T.date(2026, 10, 4), category: B.eatingOutID)
        refund.isRefund = true
        refund.refundOfID = expense.id
        try repository.saveTransaction(refund)
        #expect(try detail(budget, repository: repository).transactions.map(\.title) == ["Refund", "Expense"])
    }

    @Test("#25 AC 6: a reload shows a new expense straight away")
    func reloads() throws {
        let budget = B.budget("Eating out", limit: 9_500)
        let repository = try B.repository([budget])
        let model = try detail(budget, repository: repository)
        #expect(model.header?.headline == "Nothing spent yet")
        try repository.saveTransaction(B.expense(500))
        model.load()
        #expect(model.header?.headline == "₹9,000.00 left")
        #expect(model.transactions.count == 1)
    }
}

@Suite("Budget detail dates (#25)")
struct BudgetDetailDatesTests {
    @Test("#177 review NB1: ranges are the platform's interval format, unchanged, in any language")
    func platformRanges() {
        let period = BudgetSchedule(startDay: CalendarDay(year: 2026, month: 9, day: 28), recurrence: .weekly)
            .period(0)
        for identifier in ["en_IN", "de_DE", "fr_FR", "hi_IN"] {
            let locale = Locale(identifier: identifier)
            let formatter = DateIntervalFormatter()
            formatter.locale = locale
            formatter.calendar = BudgetDays.calendar
            formatter.timeZone = BudgetDays.calendar.timeZone
            formatter.dateTemplate = "dMMMy"
            let expected = formatter.string(from: BudgetDays.date(period.start), to: BudgetDays.date(period.end))
            #expect(BudgetDetailDates(locale: locale).range(period) == expected, "\(identifier)")
        }
    }
}
