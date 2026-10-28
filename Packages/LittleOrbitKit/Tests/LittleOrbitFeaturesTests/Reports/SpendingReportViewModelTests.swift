import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// A fake report source over a fixed snapshot, so the view model is tested against the use-case protocol only.
@MainActor
final class FakeSpendingReportUseCase: LoadSpendingReportUseCase {
    var snapshot: LedgerSnapshot
    var fails = false
    private(set) var requests: [SpendingReportQuery] = []
    private(set) var entryRequests: [SpendingReportQuery] = []

    init(snapshot: LedgerSnapshot) {
        self.snapshot = snapshot
    }

    struct Failure: Error {}

    func spendingReport(_ query: SpendingReportQuery) async throws -> SpendingReport {
        requests.append(query)
        if fails {
            throw Failure()
        }
        return SpendingReportBuilder.report(in: snapshot, query: query, defaultCurrency: "INR")
    }

    func spendingEntries(_ query: SpendingReportQuery, categoryID: UUID?) async throws -> [SpendingReportEntry] {
        entryRequests.append(query)
        if fails {
            throw Failure()
        }
        return SpendingReportBuilder.entries(in: snapshot, query: query, categoryID: categoryID)
    }
}

/// Made-up data in Asia/Calcutta: invented names only.
@MainActor
enum SpendingFixture {
    static let zone = "Asia/Calcutta"
    static let savings = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR")
    static let usdWallet = Account(name: "USD Wallet", type: .checking, currencyCode: "USD")
    static let food = TransactionCategory(name: "Food & Dining", iconName: "fork.knife")
    static let groceries = TransactionCategory(name: "Groceries", parentID: food.id, iconName: "cart.fill")
    static let rent = TransactionCategory(name: "Rent", iconName: "house.fill")
    static let electronics = TransactionCategory(name: "Electronics", iconName: "bolt.fill")
    static let payee = Payee(name: "Green Basket")
    static let trailhead = Payee(name: "Trailhead Sports")
    static let locale = Locale(identifier: "en_IN")

    static func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    static func expense(
        _ amount: String,
        _ category: TransactionCategory?,
        _ month: Int,
        _ day: Int,
        account: Account = savings,
        payee: Payee? = nil,
    ) -> Transaction {
        Transaction(
            type: .expense,
            amount: Decimal(string: amount)!,
            date: date(month, day),
            timeZoneID: zone,
            accountID: account.id,
            categoryID: category?.id,
            payeeID: payee?.id,
        )
    }

    static func refund(
        _ amount: String,
        _ category: TransactionCategory?,
        _ month: Int,
        _ day: Int,
        payee: Payee? = nil,
        details: String? = nil,
        of original: Transaction? = nil,
    ) -> Transaction {
        Transaction(
            type: .income,
            amount: Decimal(string: amount)!,
            date: date(month, day),
            timeZoneID: zone,
            accountID: savings.id,
            categoryID: category?.id,
            payeeID: payee?.id,
            details: details,
            refundOfID: original?.id,
            isRefund: true,
        )
    }

    static func snapshot(_ transactions: [Transaction]) -> LedgerSnapshot {
        LedgerSnapshot(
            accounts: [savings, usdWallet],
            transactions: transactions,
            categories: [food, groceries, rent, electronics],
            payees: [payee, trailhead],
        )
    }

    static func model(_ useCase: any LoadSpendingReportUseCase) -> SpendingReportViewModel {
        SpendingReportViewModel(
            useCase: useCase,
            locale: locale,
            timeZone: TimeZone(identifier: zone)!,
            now: { date(10, 25) },
        )
    }
}

@MainActor
@Suite("Spending report view model (#27 core)")
struct SpendingReportViewModelTests {
    typealias S = SpendingFixture  // swiftlint:disable:this type_name

    @Test("This Month is the default; rows show name, amount, share, count and a bar against the largest")
    func rows() async {
        let fake = FakeSpendingReportUseCase(
            snapshot: S.snapshot([
                S.expense("45000", S.rent, 10, 1),
                S.expense("12450.50", S.groceries, 10, 3),
                S.expense("3200", nil, 10, 8),
            ])
        )
        let model = S.model(fake)
        #expect(model.isLoading)
        await model.load()
        #expect(!model.isLoading)
        #expect(model.period == .thisMonth)
        #expect(model.periodTitle == "October 2026")
        #expect(model.totalText == "₹60,650.50")
        #expect(model.totalCaption == "Spent in October 2026 · all accounts · INR")
        #expect(model.rows.map(\.name) == ["Rent", "Food & Dining › Groceries", "Uncategorised"])
        #expect(model.rows.map(\.amountText) == ["₹45,000.00", "₹12,450.50", "₹3,200.00"])
        #expect(model.rows.map(\.shareText) == ["74.2%", "20.5%", "5.3%"])
        #expect(model.rows.map(\.countText) == ["1 transaction", "1 transaction", "1 transaction"])
        #expect(model.rows.first?.barFraction == 1)
        #expect(model.rows.last?.symbolName == "questionmark")
        #expect(model.rows.last?.hue == .gray)
        #expect(!model.showsCurrencyPicker)
        #expect(!model.isEmpty)
    }

    @Test("VoiceOver reads each row as a table line: name, amount, currency, share and count")
    func accessibility() async {
        let fake = FakeSpendingReportUseCase(snapshot: S.snapshot([S.expense("12450.50", S.groceries, 10, 3)]))
        let model = S.model(fake)
        await model.load()
        let label = model.rows.first?.accessibilityLabel ?? ""
        #expect(label.hasPrefix("Food & Dining › Groceries, ₹12,450.50, "))
        #expect(label.hasSuffix(", 100.0%, 1 transaction"))
        #expect(label.contains("Indian"))
    }

    @Test("A refund-only row is negative, last, has no bar and still lowers the total")
    func negativeRow() async throws {
        let fake = FakeSpendingReportUseCase(
            snapshot: S.snapshot([
                S.expense("1000", S.rent, 10, 1),
                S.refund("300", S.electronics, 10, 4),
            ])
        )
        let model = S.model(fake)
        await model.load()
        #expect(model.rows.map(\.name) == ["Rent", "Electronics"])
        #expect(model.rows.last?.amountText == "−₹300.00")
        #expect(model.rows.last?.barFraction == nil)
        #expect(model.rows.last?.amountTone == .negative)
        #expect(model.totalText == "₹700.00")
        // The minus sign comes from the percent format style in the locale (NB8), not added in front.
        let negative = (Decimal(-429) / 1000).formatted(.percent.precision(.fractionLength(1)).locale(S.locale))
        #expect(model.rows.map(\.shareText) == ["142.9%", negative])
        #expect(negative != "42.9%" && negative.contains("42.9%"))
        // The drill-down header carries the same signed share (D319.7).
        let refunds = try #require(model.rows.last)
        #expect(
            try #require(await model.drillDown(for: refunds)).caption
                == "\(negative) of spending · October 2026 · all accounts · INR"
        )
    }

    @Test("Bars are a fraction of the largest row")
    func barFractions() async throws {
        let fake = FakeSpendingReportUseCase(
            snapshot: S.snapshot([S.expense("400", S.rent, 10, 1), S.expense("100", S.groceries, 10, 2)])
        )
        let model = S.model(fake)
        await model.load()
        let fractions = model.rows.map(\.barFraction)
        #expect(fractions == [1, 0.25])
    }

    @Test("Changing the period reloads: Last Month, This Year and Last Year")
    func periods() async {
        let fake = FakeSpendingReportUseCase(
            snapshot: S.snapshot([
                S.expense("100", S.rent, 10, 1),
                S.expense("200", S.rent, 9, 30),
                Transaction(
                    type: .expense,
                    amount: 50,
                    date: S.date(12, 31, year: 2025),
                    timeZoneID: S.zone,
                    accountID: S.savings.id,
                    categoryID: S.rent.id,
                ),
            ])
        )
        let model = S.model(fake)
        await model.load()
        #expect(model.totalText == "₹100.00")
        await model.select(.lastMonth)
        #expect(model.periodTitle == "September 2026")
        #expect(model.totalText == "₹200.00")
        await model.select(.thisYear)
        #expect(model.periodTitle == "2026")
        #expect(model.totalText == "₹300.00")
        await model.select(.lastYear)
        #expect(model.periodTitle == "2025")
        #expect(model.totalText == "₹50.00")
        #expect(
            model.periods.map(model.periodName) == [
                "This Month", "Last Month", "This Quarter", "Last Quarter", "This Year", "Last Year",
            ]
        )
    }

    @Test("Several currencies show the picker, default first; picking one shows only that currency")
    func currencies() async {
        let fake = FakeSpendingReportUseCase(
            snapshot: S.snapshot([
                S.expense("1000", S.rent, 10, 1),
                S.expense("80", S.groceries, 10, 3, account: S.usdWallet),
            ])
        )
        let model = S.model(fake)
        await model.load()
        #expect(model.showsCurrencyPicker)
        #expect(model.currencies == ["INR", "USD"])
        #expect(model.currencyCode == "INR")
        await model.selectCurrency("USD")
        #expect(model.currencyCode == "USD")
        #expect(model.totalText == "$80.00")
        #expect(model.rows.map(\.name) == ["Food & Dining › Groceries"])
        await model.select(.thisYear)
        #expect(model.currencyCode == "USD")
        #expect(fake.requests.last?.currencyCode == "USD")
    }

    @Test("A period with no expenses shows the empty state: No Expenses, then the message (D318.4)")
    func empty() async {
        let fake = FakeSpendingReportUseCase(snapshot: S.snapshot([S.expense("100", S.rent, 9, 1)]))
        let model = S.model(fake)
        await model.load()
        #expect(model.isEmpty)
        #expect(model.rows.isEmpty)
        #expect(model.emptyTitle == "No Expenses")
        #expect(model.emptyMessage == "There are no expenses in this period. Try another period.")
    }

    @Test("A read failure shows Couldn’t Load Report, not the empty state")
    func failure() async {
        let fake = FakeSpendingReportUseCase(snapshot: S.snapshot([]))
        fake.fails = true
        let model = S.model(fake)
        await model.load()
        #expect(model.loadFailed)
        #expect(!model.isEmpty)
        #expect(model.loadFailedTitle == "Couldn’t Load Report")
        #expect(model.loadFailedMessage == "Try again.")
        #expect(model.periodTitle == "October 2026")
    }

    @Test("The drill-down lists the row's transactions, newest first, adding up to the row")
    func drillDown() async throws {
        let fake = FakeSpendingReportUseCase(
            snapshot: S.snapshot([
                S.expense("2000", S.groceries, 10, 3, payee: S.payee),
                S.expense("1240", S.groceries, 10, 20),
                S.refund("100", S.groceries, 10, 10),
                S.expense("500", S.food, 10, 5),
            ])
        )
        let model = S.model(fake)
        await model.load()
        let row = try #require(model.rows.first { $0.name == "Food & Dining › Groceries" })
        #expect(row.amountText == "₹3,140.00")
        let drill = try #require(await model.drillDown(for: row))
        #expect(drill.title == "Food & Dining › Groceries")
        #expect(drill.amountText == row.amountText)
        #expect(drill.caption == "86.3% of spending · October 2026 · all accounts · INR")
        #expect(drill.countText == "3 transactions")
        #expect(drill.entries.map(\.title) == ["Expense", "Refund (original deleted)", "Green Basket"])
        #expect(drill.entries.map(\.amountText) == ["−₹1,240.00", "+₹100.00", "−₹2,000.00"])
        #expect(
            drill.entries.map(\.subtitle) == [
                "Everyday Savings · Tue, 20 Oct", "Everyday Savings · Sat, 10 Oct",
                "Everyday Savings · Sat, 3 Oct",
            ]
        )
    }

    @Test(
        "Refund rows take D233's titles: with or without a payee, linked or with the original deleted, and the description fallback (D318.6)"
    )
    func refundTitles() async throws {
        let original = S.expense("2000", S.electronics, 10, 2, payee: S.trailhead)
        let fake = FakeSpendingReportUseCase(
            snapshot: S.snapshot([
                original,
                S.refund("100", S.electronics, 10, 3, payee: S.trailhead, of: original),
                S.refund("200", S.electronics, 10, 4, payee: S.trailhead),
                S.refund("300", S.electronics, 10, 5, of: original),
                S.refund("400", S.electronics, 10, 6),
                S.refund("500", S.electronics, 10, 7, details: "  R1 Trailhead refund  ", of: original),
                S.refund("600", S.electronics, 10, 8, details: "R1 Trailhead refund"),
                S.refund("700", S.electronics, 10, 9, details: "   "),
            ])
        )
        let model = S.model(fake)
        await model.load()
        let row = try #require(model.rows.first { $0.name == "Electronics" })
        let drill = try #require(await model.drillDown(for: row))
        #expect(
            drill.entries.map(\.title) == [
                "Refund (original deleted)",
                "Refund (original deleted) · R1 Trailhead refund",
                "Refund · R1 Trailhead refund",
                "Refund (original deleted)",
                "Refund",
                "Refund (original deleted) · Trailhead Sports",
                "Refund · Trailhead Sports",
                "Trailhead Sports",
            ]
        )
        #expect(drill.entries.allSatisfy { !$0.subtitle.contains("Refund") })
        #expect(drill.entries.first?.accessibilityLabel.hasPrefix("Refund (original deleted), ") == true)
    }

    @Test("NB9: an open drill-down reads again after every load, even when no row changed (a payee rename)")
    func drillDownAfterRename() async throws {
        let fake = FakeSpendingReportUseCase(
            snapshot: S.snapshot([S.expense("2000", S.groceries, 10, 3, payee: S.payee)])
        )
        let model = S.model(fake)
        await model.load()
        let row = try #require(model.rows.first)
        let before = try #require(await model.drillDown(for: row))
        #expect(before.entries.map(\.title) == ["Green Basket"])
        let revision = model.revision
        let rows = model.rows
        fake.snapshot.payees = fake.snapshot.payees.map { payee in
            var renamed = payee
            renamed.name = "Green Basket Market"
            return renamed
        }
        await model.load()
        #expect(model.rows == rows)
        #expect(model.revision == revision + 1)
        let after = try #require(await model.drillDown(for: row))
        #expect(after.entries.map(\.title) == ["Green Basket Market"])
    }

    @Test("Food & Dining's drill-down holds only its own transaction, not its subcategory's (D289)")
    func parentDrillDown() async throws {
        let fake = FakeSpendingReportUseCase(
            snapshot: S.snapshot([S.expense("2000", S.groceries, 10, 3), S.expense("500", S.food, 10, 5)])
        )
        let model = S.model(fake)
        await model.load()
        let row = try #require(model.rows.first { $0.name == "Food & Dining" })
        let drill = try #require(await model.drillDown(for: row))
        #expect(drill.entries.count == 1)
        #expect(drill.amountText == "₹500.00")
    }

    @Test("Wired to the real use case over the in-memory store, it reads saved transactions")
    func realUseCase() async throws {
        let repository = InMemoryLedgerRepository()
        try repository.saveAccount(S.savings)
        try repository.saveCategory(S.rent)
        try repository.saveTransaction(S.expense("45000", S.rent, 10, 1))
        try repository.saveTransaction(S.expense("0.01", S.rent, 10, 2))
        let useCase = DefaultLoadSpendingReportUseCase(source: repository, defaultCurrency: "INR")
        let model = S.model(useCase)
        await model.load()
        #expect(model.totalText == "₹45,000.01")
        #expect(model.rows.map(\.countText) == ["2 transactions"])
    }

    @Test("The Reports feature makes a report model with This Month selected")
    func feature() async {
        let feature = ReportsFeature(
            spendingReport: FakeSpendingReportUseCase(snapshot: S.snapshot([])),
            updates: LedgerUpdates(),
        )
        #expect(feature.title == "Reports")
        #expect(feature.spendingQuestion == "What do I spend my money on?")
        #expect(feature.makeSpendingReport().period == .thisMonth)
    }
}
