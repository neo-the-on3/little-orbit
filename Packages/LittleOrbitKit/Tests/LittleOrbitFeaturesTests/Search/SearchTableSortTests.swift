import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// #187: the macOS table's sort, with day headers only for a date sort (S63). Today is Tue 20 Oct 2026 in India. All names and amounts are made up.
@MainActor
@Suite("Search table sort")
struct SearchTableSortTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    static let dining = TransactionCategory(name: "Coffee Runs")
    static let copperCup = Payee(name: "Copper Cup Cafe")
    static let bakery = Payee(name: "Bakery Lane")

    private func repository() throws -> InMemoryLedgerRepository {
        let repository = try F.repository()
        try repository.saveCategory(Self.dining)
        try repository.savePayee(Self.copperCup)
        try repository.savePayee(Self.bakery)
        for (amount, day, payee) in [
            (Decimal(350), 25, Self.copperCup), (320, 20, Self.copperCup), (90, 19, Self.bakery),
            (410, 17, Self.copperCup), (999, 15, Self.bakery),
        ] {
            try repository.saveTransaction(
                F.expense(amount, on: F.date(2026, 10, day), category: Self.dining.id, payee: payee.id)
            )
        }
        return repository
    }

    private func model(
        _ repository: InMemoryLedgerRepository,
        query: String,
    ) -> TransactionSearchViewModel {
        let model = TransactionSearchViewModel(
            search: DefaultSearchTransactionsUseCase(repository: repository),
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
            defaultCurrency: "INR",
        )
        model.query = query
        model.load()
        return model
    }

    // MARK: Table sort

    @Test("S63: a date sort shows day headers, newest first by default, and oldest first when reversed")
    func dateSort() throws {
        let model = model(try repository(), query: "")
        #expect(model.showsDayHeaders)
        #expect(model.tableRows.isEmpty)
        #expect(model.tableSections.map(\.header.title) == model.sections.map(\.title))
        #expect(model.tableSections.flatMap(\.rows).map(\.row) == model.sections.flatMap(\.rows))

        model.sortOrder = [KeyPathComparator(\SearchTableRow.date, order: .forward)]
        #expect(model.showsDayHeaders)
        #expect(model.tableSections.map(\.header.title) == model.sections.reversed().map(\.title))
        let amounts = model.tableSections.flatMap(\.rows).map(\.amount)
        #expect(amounts == [-999, -410, -90, -320, -350])
        #expect(model.tableSections.first?.header.isUpcoming == false)
        #expect(model.tableSections.last?.header.isUpcoming == true)
    }

    @Test("S63: sorting by Amount or Payee lists the rows flat, with no headers; Date brings the headers back")
    func otherSorts() throws {
        let model = model(try repository(), query: "")
        model.sortOrder = [KeyPathComparator(\SearchTableRow.amount, order: .forward)]
        #expect(!model.showsDayHeaders)
        #expect(model.tableSections.isEmpty)
        #expect(model.tableRows.map(\.amount) == [-999, -410, -350, -320, -90])

        model.sortOrder = [KeyPathComparator(\SearchTableRow.payee, order: .forward)]
        #expect(!model.showsDayHeaders)
        #expect(model.tableRows.map(\.payee).first == "Bakery Lane")
        #expect(model.tableRows.count == 5)

        for column in [
            KeyPathComparator(\SearchTableRow.descriptionText), KeyPathComparator(\SearchTableRow.category),
            KeyPathComparator(\SearchTableRow.account),
        ] {
            model.sortOrder = [column]
            #expect(!model.showsDayHeaders)
            #expect(model.tableSections.isEmpty)
            #expect(model.tableRows.count == 5)
        }

        model.sortOrder = [KeyPathComparator(\SearchTableRow.date, order: .reverse)]
        #expect(model.showsDayHeaders)
        #expect(model.tableRows.isEmpty)
        #expect(model.tableSections.count == model.sections.count)
    }

    @Test("A new query keeps the chosen sort, and the upcoming row's date is marked for the muted cell")
    func sortSurvivesTyping() throws {
        let model = model(try repository(), query: "")
        model.sortOrder = [KeyPathComparator(\SearchTableRow.amount, order: .reverse)]
        model.query = "copper"
        model.load()
        #expect(model.tableRows.map(\.amount) == [-320, -350, -410])
        #expect(model.tableRows.filter(\.isUpcoming).map(\.amount) == [-350])
    }

    // MARK: Description and Payee columns (D325.4, D326.2)

    @Test("D326.2: Description shows the description and Payee only the payee, blank when there's none")
    func descriptionAndPayee() throws {
        let repository = try F.repository()
        try repository.savePayee(Self.copperCup)
        let both = F.expense(
            120,
            on: F.date(2026, 10, 18),
            payee: Self.copperCup.id,
            details: "  Flat white for two  ",
        )
        let payeeOnly = F.expense(80, on: F.date(2026, 10, 17), payee: Self.copperCup.id)
        let detailsOnly = F.expense(45, on: F.date(2026, 10, 16), details: "Parking meter")
        let neither = F.expense(10, on: F.date(2026, 10, 15))
        for transaction in [both, payeeOnly, detailsOnly, neither] {
            try repository.saveTransaction(transaction)
        }
        let rows = model(repository, query: "").tableSections.flatMap(\.rows)
        func cells(_ transaction: Transaction) throws -> [String] {
            let row = try #require(rows.first { $0.id == transaction.id })
            return [row.descriptionText, row.payee]
        }
        #expect(try cells(both) == ["Flat white for two", "Copper Cup Cafe"])
        #expect(try cells(payeeOnly) == ["Expense", "Copper Cup Cafe"])
        #expect(try cells(detailsOnly) == ["Parking meter", ""])
        #expect(try cells(neither) == ["Expense", ""])
        // D328: only the fallback is marked for the secondary style.
        let fallbacks = rows.filter(\.isDescriptionFallback).map(\.id)
        #expect(Set(fallbacks) == [payeeOnly.id, neither.id])
        // The list row keeps its own title: the payee first (D173.9).
        #expect(try #require(rows.first { $0.id == both.id }).row.title == "Copper Cup Cafe")
    }

    @Test("D320.7: a transfer's Description is To or From the other account, from the listed side; Payee is blank")
    func transferDescription() throws {
        let repository = try F.repository()
        let sent = F.transfer(1_000, on: F.date(2026, 10, 18), from: F.savingsID, to: F.walletID, details: "Cash")
        try repository.saveTransaction(sent)
        let combined = try #require(model(repository, query: "").tableSections.first?.rows.first)
        #expect(combined.descriptionText == "To Corner Wallet")
        #expect(combined.payee.isEmpty)

        let wallet = TransactionSearchViewModel(
            search: DefaultSearchTransactionsUseCase(repository: repository),
            accountID: F.walletID,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
            defaultCurrency: "INR",
        )
        wallet.load()
        let received = try #require(wallet.tableSections.first?.rows.first)
        #expect(received.descriptionText == "From Everyday Savings")
        #expect(received.payee.isEmpty)
    }

    @Test("D233: a refund's Description is its refund title, named by the payee, else the description")
    func refundDescription() throws {
        let repository = try F.repository()
        try repository.saveCategory(Self.dining)
        try repository.savePayee(Self.copperCup)
        let expense = F.expense(600, on: F.date(2026, 10, 12), category: Self.dining.id, payee: Self.copperCup.id)
        try repository.saveTransaction(expense)
        let linked = refund(200, on: F.date(2026, 10, 14), of: expense, payee: Self.copperCup.id)
        let unnamed = refund(50, on: F.date(2026, 10, 15), of: expense)
        let described = refund(100, on: F.date(2026, 10, 16), of: nil, details: "Returned mugs")
        let bare = refund(30, on: F.date(2026, 10, 17), of: nil)
        for transaction in [linked, unnamed, described, bare] {
            try repository.saveTransaction(transaction)
        }
        let rows = model(repository, query: "").tableSections.flatMap(\.rows)
        func cells(_ transaction: Transaction) throws -> [String] {
            let row = try #require(rows.first { $0.id == transaction.id })
            return [row.descriptionText, row.payee]
        }
        #expect(try cells(linked) == ["Refund · Copper Cup Cafe", "Copper Cup Cafe"])
        #expect(try cells(unnamed) == ["Refund", ""])
        #expect(try cells(described) == ["Refund (original deleted) · Returned mugs", ""])
        #expect(try cells(bare) == ["Refund (original deleted)", ""])
        #expect(try cells(expense) == ["Expense", "Copper Cup Cafe"])
        #expect(rows.filter(\.isDescriptionFallback).map(\.id) == [expense.id])
    }

    @Test("Sorting by Description or Payee orders by those cells, so a blank payee sorts first")
    func descriptionAndPayeeSort() throws {
        let repository = try F.repository()
        try repository.savePayee(Self.copperCup)
        try repository.savePayee(Self.bakery)
        for transaction in [
            F.expense(10, on: F.date(2026, 10, 18), payee: Self.copperCup.id, details: "Muffins"),
            F.expense(20, on: F.date(2026, 10, 17), payee: Self.bakery.id, details: "Bread"),
            F.expense(30, on: F.date(2026, 10, 16), details: "Auto rickshaw"),
        ] {
            try repository.saveTransaction(transaction)
        }
        let model = model(repository, query: "")
        model.sortOrder = [KeyPathComparator(\SearchTableRow.descriptionText)]
        #expect(model.tableRows.map(\.descriptionText) == ["Auto rickshaw", "Bread", "Muffins"])
        model.sortOrder = [KeyPathComparator(\SearchTableRow.payee, order: .reverse)]
        #expect(model.tableRows.map(\.payee) == ["Copper Cup Cafe", "Bakery Lane", ""])
    }

    @Test("D328: a row with no description shows Expense or Income, and the Description sort uses that text")
    func descriptionFallbackSort() throws {
        let repository = try F.repository()
        try repository.savePayee(Self.copperCup)
        let muffins = F.expense(10, on: F.date(2026, 10, 18), payee: Self.copperCup.id, details: "Muffins")
        let bare = F.expense(20, on: F.date(2026, 10, 17), payee: Self.copperCup.id)
        let auto = F.expense(30, on: F.date(2026, 10, 16), details: "Auto rickshaw")
        let salary = F.income(5_000, on: F.date(2026, 10, 15))
        for transaction in [muffins, bare, auto, salary] {
            try repository.saveTransaction(transaction)
        }
        let model = model(repository, query: "")
        model.sortOrder = [KeyPathComparator(\SearchTableRow.descriptionText)]
        #expect(model.tableRows.map(\.descriptionText) == ["Auto rickshaw", "Expense", "Income", "Muffins"])
        #expect(model.tableRows.map(\.isDescriptionFallback) == [false, true, true, false])
        model.sortOrder = [KeyPathComparator(\SearchTableRow.descriptionText, order: .reverse)]
        #expect(model.tableRows.map(\.id) == [muffins.id, salary.id, bare.id, auto.id])
    }

    private func refund(
        _ amount: Decimal,
        on date: Date,
        of expense: Transaction?,
        payee: UUID? = nil,
        details: String? = nil,
    ) -> Transaction {
        Transaction(
            type: .income,
            amount: amount,
            date: date,
            timeZoneID: F.zoneID,
            accountID: F.savingsID,
            categoryID: expense?.categoryID ?? Self.dining.id,
            payeeID: payee,
            details: details,
            refundOfID: expense?.id,
            isRefund: true,
            createdAt: date,
        )
    }
}
