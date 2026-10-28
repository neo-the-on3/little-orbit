import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// The spending chart and its audio graph (#184 slice 3, UI Designer's spec). Made-up data only.
@MainActor
@Suite("Spending report chart (#184 slice 3)")
struct SpendingChartTests {
    typealias S = SpendingFixture  // swiftlint:disable:this type_name

    static let travel = TransactionCategory(name: "Travel", iconName: "airplane")
    static let health = TransactionCategory(name: "Health", iconName: "heart.fill")
    static let books = TransactionCategory(name: "Books", iconName: "book.fill")
    static let gifts = TransactionCategory(name: "Gifts", iconName: "gift.fill")

    static func snapshot(_ transactions: [Transaction]) -> LedgerSnapshot {
        var snapshot = S.snapshot(transactions)
        snapshot.categories += [travel, health, books, gifts]
        return snapshot
    }

    /// Seven categories: Rent, Travel, Groceries, Health, Electronics, Books and Gifts, largest first.
    static let seven = [
        S.expense("45000", S.rent, 10, 1),
        S.expense("12450.50", travel, 10, 2),
        S.expense("8000", S.groceries, 10, 3),
        S.expense("4000", health, 10, 4),
        S.expense("2000", S.electronics, 10, 5),
        S.expense("1449", books, 10, 6),
        S.expense("1000", gifts, 10, 7),
    ]

    @Test("Given 7 expense categories, then the chart has the 5 largest bars plus Other · 2 categories")
    func sevenCategories() async throws {
        let model = S.model(FakeSpendingReportUseCase(snapshot: Self.snapshot(Self.seven)))
        await model.load()
        #expect(model.rows.count == 7)
        #expect(
            model.chartBars.map(\.name)
                == ["Rent", "Travel", "Food & Dining › Groceries", "Health", "Electronics", "Other · 2 categories"]
        )
        // The bars add up to the total.
        #expect(model.chartBars.map(\.amount).reduce(0, +) == 73_899.5)
        let other = try #require(model.chartBars.last)
        #expect(other.row == nil)
        #expect(other.hue == nil)
        #expect(other.amountText == "₹2,449.00")
        #expect(other.accessibilityLabel == "Other, 2 categories")
        // Other's share is the two shares it combines: 2.0% + 1.4%, from the rows' largest-remainder shares.
        #expect(model.rows.suffix(2).compactMap(\.shareText) == ["2.0%", "1.4%"])
        #expect(other.accessibilityValue == "₹2,449.00, 3.4%")
        #expect(other.shareText == "3.4%")
    }

    @Test("A bar reads as one element: its name, then its amount and share; a tap on it opens its row's drill-down")
    func barReading() async throws {
        let model = S.model(FakeSpendingReportUseCase(snapshot: Self.snapshot(Self.seven)))
        await model.load()
        let rent = try #require(model.chartBars.first)
        #expect(rent.accessibilityLabel == "Rent")
        #expect(rent.accessibilityValue == "₹45,000.00, 60.9%")
        #expect(rent.hue == model.rows.first?.hue)
        #expect(model.chartRow(id: rent.id) == model.rows.first)
        #expect(model.chartRow(id: "other") == nil)
        #expect(model.chartRow(id: "Rent") == nil, "a tap resolves by ID, never by name")
        // The annotation is compact; the list keeps the full amount.
        #expect(rent.compactAmountText != rent.amountText)
        #expect(rent.compactAmountText.contains("45"))
    }

    @Test("Given exactly 6 categories, then the 6th has its own bar by name and there's no Other")
    func sixCategories() async {
        let model = S.model(FakeSpendingReportUseCase(snapshot: Self.snapshot(Array(Self.seven.prefix(6)))))
        await model.load()
        #expect(model.chartBars.count == 6)
        #expect(model.chartBars.last?.name == "Books")
        #expect(model.chartBars.allSatisfy { $0.row != nil })
    }

    @Test("A refund-only row has no bar but stays in the list, with its locale-minus share")
    func refundRow() async {
        let model = S.model(
            FakeSpendingReportUseCase(
                snapshot: Self.snapshot([S.expense("1000", S.rent, 10, 1), S.refund("300", S.electronics, 10, 2)])
            )
        )
        await model.load()
        #expect(model.rows.count == 2)
        #expect(model.chartBars.map(\.name) == ["Rent"])
        #expect(model.rows.last?.shareText == "-42.9%")
    }

    @Test("The audio graph: the report title, the caption as summary, Category and Amount axes in the currency")
    func audioGraph() async {
        let model = S.model(FakeSpendingReportUseCase(snapshot: Self.snapshot(Self.seven)))
        await model.load()
        #expect(model.chartTitle == "What do I spend my money on?")
        #expect(model.chartSummary == "Spent in October 2026 · all accounts · INR")
        #expect(model.chartCategoryAxis == "Category")
        #expect(model.chartAmountAxis == "Amount")
        #expect(model.chartAmountText(12_450.5) == "₹12,450.50")
    }

    @Test(
        "Given a category I named “Uncategorised” and uncategorised spending, when the chart shows, then there are two bars, each tap opens its own row, and the audio graph has two points"
    )
    func duplicateNames() async throws {
        let lookalike = TransactionCategory(name: "Uncategorised", iconName: "tag.fill")
        var snapshot = Self.snapshot([S.expense("500", lookalike, 10, 1), S.expense("300", nil, 10, 2)])
        snapshot.categories.append(lookalike)
        let model = S.model(FakeSpendingReportUseCase(snapshot: snapshot))
        await model.load()
        #expect(model.rows.map(\.name) == ["Uncategorised", "Uncategorised"])
        #expect(model.chartBars.map(\.name) == ["Uncategorised", "Uncategorised"])
        #expect(Set(model.chartBars.map(\.id)).count == 2)
        let mine = try #require(model.chartBars.first)
        let none = try #require(model.chartBars.last)
        #expect(mine.id == lookalike.id.uuidString)
        #expect(model.chartRow(id: mine.id)?.categoryID == lookalike.id)
        #expect(model.chartRow(id: none.id) == model.rows.last)
        #expect(model.chartRow(id: none.id)?.categoryID == nil)
        #expect(model.chartBar(id: none.id)?.amountText == "₹300.00")
        let points = model.chartAudioPoints
        #expect(points.map(\.id) == model.chartBars.map(\.id))
        #expect(points.map(\.category) == ["Uncategorised", "Uncategorised (2)"])
        #expect(points.map(\.label) == ["₹500.00, 62.5%", "₹300.00, 37.5%"])
    }

    @Test("The audio graph has one point per bar, in the chart's order, Other last")
    func audioPoints() async {
        let model = S.model(FakeSpendingReportUseCase(snapshot: Self.snapshot(Self.seven)))
        await model.load()
        let points = model.chartAudioPoints
        #expect(points.count == model.chartBars.count)
        #expect(points.map(\.id) == model.chartBars.map(\.id))
        #expect(points.map(\.amount) == model.chartBars.map(\.amount))
        #expect(points.last?.category == "Other, 2 categories")
        #expect(points.first?.category == "Rent")
    }

    @Test("The Mac table's columns are Category, Transactions, Amount and Share; Transactions is a number")
    func tableColumns() async {
        let model = S.model(FakeSpendingReportUseCase(snapshot: Self.snapshot(Self.seven)))
        await model.load()
        #expect(
            [model.chartCategoryAxis, model.transactionsColumn, model.chartAmountAxis, model.shareColumn]
                == ["Category", "Transactions", "Amount", "Share"]
        )
        #expect(model.rows.first?.countNumberText == "1")
    }

    @Test("With no expenses there are no bars")
    func empty() async {
        let model = S.model(FakeSpendingReportUseCase(snapshot: Self.snapshot([])))
        await model.load()
        #expect(model.chartBars.isEmpty)
    }
}

/// Full amounts in en_IN (UI Designer's answer on #310): the rows, the Mac table and the audio graph use the
/// locale's currency formatter, so they get lakh grouping; only the bars' annotations are compact.
@MainActor
@Suite("Spending report amounts in en_IN (#184 slice 3)")
struct SpendingLakhTests {
    typealias S = SpendingFixture  // swiftlint:disable:this type_name

    @Test("Given ₹1,23,456.00 of rent in en_IN, the total, row, bar and audio graph use lakh grouping")
    func lakhGrouping() async throws {
        let model = S.model(FakeSpendingReportUseCase(snapshot: S.snapshot([S.expense("123456", S.rent, 10, 1)])))
        await model.load()
        #expect(model.totalText == "₹1,23,456.00")
        let row = try #require(model.rows.first)
        #expect(row.amountText == "₹1,23,456.00")
        #expect(row.accessibilityLabel.hasPrefix("Rent, ₹1,23,456.00, "))
        let bar = try #require(model.chartBars.first)
        #expect(bar.amountText == "₹1,23,456.00")
        #expect(bar.accessibilityValue == "₹1,23,456.00, 100.0%")
        #expect(model.chartAmountText(123_456) == "₹1,23,456.00")
        // The annotation keeps the system's compact form.
        #expect(bar.compactAmountText != bar.amountText)
    }
}
