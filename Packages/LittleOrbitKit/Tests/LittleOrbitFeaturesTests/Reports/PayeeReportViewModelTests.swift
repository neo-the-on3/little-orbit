import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// “Where do I spend the most?” (#184 slice 4, UI Designer's spec): the spending report's screen grouped by
/// payee, with the slice 1 filters and the slice 3 chart. Made-up data only.
@MainActor
@Suite("Spending by payee view model (#184 slice 4)")
struct PayeeReportViewModelTests {
    typealias S = SpendingFixture  // swiftlint:disable:this type_name

    static let sunrise = Payee(name: "Sunrise Apartments")
    static let names = ["Corner Cafe", "Daily Fuel", "Book Nook", "Gift Barn", "Pet Parlour"]
    static let more = names.map { Payee(name: $0) }

    static func expense(_ amount: String, _ payee: Payee?, day: Int, category: TransactionCategory = S.rent)
        -> Transaction
    {
        S.expense(amount, category, 10, day, payee: payee)
    }

    static func snapshot(_ transactions: [Transaction]) -> LedgerSnapshot {
        var snapshot = S.snapshot(transactions)
        snapshot.payees += [sunrise] + more
        return snapshot
    }

    static func model(_ fake: FakeSpendingReportUseCase) -> SpendingReportViewModel {
        SpendingReportViewModel(
            useCase: fake,
            grouping: .payee,
            locale: S.locale,
            timeZone: TimeZone(identifier: S.zone)!,
            now: { S.date(10, 25) },
        )
    }

    @Test("Given expenses at three payees, then rows show the payee, amount, share and count, with no icon")
    func rows() async throws {
        let fake = FakeSpendingReportUseCase(
            snapshot: Self.snapshot([
                Self.expense("45000", Self.sunrise, day: 1),
                Self.expense("12450.50", S.payee, day: 3, category: S.groceries),
                Self.expense("3200", S.trailhead, day: 8, category: S.electronics),
            ])
        )
        let model = Self.model(fake)
        await model.load()
        #expect(model.grouping == .payee)
        #expect(fake.requests.last?.grouping == .payee)
        #expect(model.rows.map(\.name) == ["Sunrise Apartments", "Green Basket", "Trailhead Sports"])
        #expect(model.rows.allSatisfy { $0.symbolName == nil })
        #expect(model.totalText == "₹60,650.50")
        #expect(model.totalCaption == "Spent in October 2026 · all accounts · INR")
        let first = try #require(model.rows.first)
        #expect(first.shareText == "74.2%")
        #expect(first.countText == "1 transaction")
        #expect(first.accessibilityLabel.hasPrefix("Sunrise Apartments, ₹45,000.00, "))
        #expect(first.accessibilityLabel.hasSuffix(", 74.2%, 1 transaction"))
    }

    @Test("The screen's wording: the question, All Payees, the payee footer and the Payee column")
    func wording() async {
        let model = Self.model(FakeSpendingReportUseCase(snapshot: Self.snapshot([])))
        #expect(model.question == "Where do I spend the most?")
        #expect(model.navigationTitle == "Spending by Payee")
        #expect(model.rowsHeader == "All Payees")
        #expect(
            model.footer
                == "Sorted by amount. Refunds reduce spending at their payee. Transfers between your accounts aren’t spending."
        )
        #expect(model.chartCategoryAxis == "Payee")
        #expect(model.chartTitle == "Where do I spend the most?")
        await model.load()
        #expect(model.isEmpty)
        #expect(model.emptyTitle == "No Expenses")
    }

    @Test("The category report keeps its own wording")
    func categoryWording() {
        let model = S.model(FakeSpendingReportUseCase(snapshot: S.snapshot([])))
        #expect(model.grouping == .category)
        #expect(model.question == "What do I spend my money on?")
        #expect(model.navigationTitle == "Spending")
        #expect(model.rowsHeader == "All Categories")
        #expect(model.chartCategoryAxis == "Category")
    }

    @Test("Transactions with no payee are one No Payee row, and its drill-down lists only them")
    func noPayee() async throws {
        let fake = FakeSpendingReportUseCase(
            snapshot: Self.snapshot([Self.expense("1000", Self.sunrise, day: 1), Self.expense("300", nil, day: 2)])
        )
        let model = Self.model(fake)
        await model.load()
        #expect(model.rows.map(\.name) == ["Sunrise Apartments", "No Payee"])
        let none = try #require(model.rows.last)
        let drill = try #require(await model.drillDown(for: none))
        #expect(drill.title == "No Payee")
        #expect(drill.amountText == "₹300.00")
        #expect(drill.entries.count == 1)
        #expect(fake.entryRequests.last?.grouping == .payee)
    }

    @Test("Drilling into a payee lists only its transactions, with the share header")
    func drillDown() async throws {
        let fake = FakeSpendingReportUseCase(
            snapshot: Self.snapshot([
                Self.expense("3000", Self.sunrise, day: 1),
                Self.expense("1000", S.payee, day: 2),
                Self.expense("500", S.payee, day: 3),
            ])
        )
        let model = Self.model(fake)
        await model.load()
        let basket = try #require(model.rows.last)
        let drill = try #require(await model.drillDown(for: basket))
        #expect(drill.title == "Green Basket")
        #expect(drill.amountText == "₹1,500.00")
        #expect(drill.entries.count == 2)
        #expect(drill.caption == "33.3% of spending · October 2026 · all accounts · INR")
    }

    @Test("D420.6: refunds over a payee's spending show −₹300.00, last, with no bar, counted in the total")
    func refundsOverSpending() async {
        let fake = FakeSpendingReportUseCase(
            snapshot: Self.snapshot([
                Self.expense("1000", Self.sunrise, day: 1),
                S.refund("300", S.electronics, 10, 4, payee: S.trailhead),
            ])
        )
        let model = Self.model(fake)
        await model.load()
        #expect(model.rows.map(\.name) == ["Sunrise Apartments", "Trailhead Sports"])
        #expect(model.rows.last?.amountText == "−₹300.00")
        #expect(model.rows.last?.barFraction == nil)
        #expect(model.totalText == "₹700.00")
        #expect(model.chartBars.map(\.name) == ["Sunrise Apartments"])
    }

    @Test("Given 7 payees, the chart has the 5 largest and Other · 2 payees")
    func chartOther() async throws {
        var transactions = [Self.expense("9000", Self.sunrise, day: 1), Self.expense("8000", S.payee, day: 2)]
        for (index, payee) in Self.more.enumerated() {
            transactions.append(Self.expense("\(7000 - index * 1000)", payee, day: 3 + index))
        }
        let model = Self.model(FakeSpendingReportUseCase(snapshot: Self.snapshot(transactions)))
        await model.load()
        #expect(model.rows.count == 7)
        let other = try #require(model.chartBars.last)
        #expect(other.name == "Other · 2 payees")
        #expect(other.accessibilityLabel == "Other, 2 payees")
        #expect(other.row == nil)
        #expect(model.chartBars.first?.hue == nil)
        #expect(model.chartBars.first?.row != nil)
    }

    @Test("The account filter applies to the payee report and its drill-downs")
    func accountFilter() async throws {
        let rewards = Account(name: "Rewards Card", type: .creditCard, currencyCode: "INR")
        var snapshot = Self.snapshot([
            Self.expense("1000", Self.sunrise, day: 1),
            S.expense("250", S.rent, 10, 3, account: rewards, payee: Self.sunrise),
        ])
        snapshot.accounts.append(rewards)
        let fake = FakeSpendingReportUseCase(snapshot: snapshot)
        let model = Self.model(fake)
        await model.load()
        #expect(model.totalText == "₹1,250.00")
        await model.setAccount(rewards.id, included: false)
        #expect(model.totalText == "₹1,000.00")
        #expect(model.totalCaption == "Spent in October 2026 · 1 of 2 accounts · INR")
        let row = try #require(model.rows.first)
        #expect(try #require(await model.drillDown(for: row)).entries.count == 1)
    }

    @Test("Reports makes the payee report, with its question for the Reports list")
    func feature() {
        let feature = ReportsFeature(
            spendingReport: FakeSpendingReportUseCase(snapshot: S.snapshot([])),
            updates: LedgerUpdates(),
        )
        #expect(feature.payeeQuestion == "Where do I spend the most?")
        #expect(feature.makePayeeReport().grouping == .payee)
        #expect(feature.makeSpendingReport().grouping == .category)
    }
}
