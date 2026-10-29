import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The #28 search screen over the real use case and an in-memory store. Today is Tue 20 Oct 2026 in India.
/// All names and amounts are made up.
@MainActor
@Suite("Search screen")
struct TransactionSearchViewModelTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    static let dining = TransactionCategory(name: "Coffee Runs")
    static let salary = TransactionCategory(name: "Side Gigs", kind: .income)
    static let copperCup = Payee(name: "Copper Cup Cafe")

    private func repository(_ transactions: [Transaction]) throws -> InMemoryLedgerRepository {
        let repository = try F.repository()
        try repository.saveCategory(Self.dining)
        try repository.saveCategory(Self.salary)
        try repository.savePayee(Self.copperCup)
        for transaction in transactions {
            try repository.saveTransaction(transaction)
        }
        return repository
    }

    private func model(
        _ repository: InMemoryLedgerRepository,
        query: String = "",
        accountID: UUID? = nil,
    ) -> TransactionSearchViewModel {
        let model = TransactionSearchViewModel(
            search: DefaultSearchTransactionsUseCase(repository: repository),
            accountID: accountID,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
            defaultCurrency: "INR",
        )
        model.query = query
        model.load()
        return model
    }

    private func cafe(_ amount: Decimal, _ day: Int, account: UUID = F.savingsID) -> Transaction {
        F.expense(
            amount,
            on: F.date(2026, 10, day),
            account: account,
            category: Self.dining.id,
            payee: Self.copperCup.id,
        )
    }

    private func cafeSample() throws -> InMemoryLedgerRepository {
        try repository([cafe(350, 25), cafe(320, 20), cafe(410, 17, account: F.cardID)])
    }

    @Test("S73, S79: the count includes upcoming; totals leave it out; the note says so (D47, D134)")
    func summary() throws {
        let model = model(try cafeSample(), query: "cafe")
        let summary = try #require(model.summary)
        #expect(summary.countText == "3 results")
        let inr = try #require(summary.lines.first)
        #expect(summary.lines.count == 1)
        #expect(inr.currencyCode == "INR")
        #expect(inr.incomeText == "₹0.00")
        #expect(inr.expensesText == "₹730.00")
        #expect(inr.netText == "−₹730.00")
        #expect(inr.movedText == nil)
        #expect(model.upcomingNote == "1 upcoming match is listed but not counted.")
        #expect(model.hasUpcoming)
    }

    @Test("D107, D120.1: days newest first; an upcoming day is muted and read as Upcoming")
    func sections() throws {
        let model = model(try cafeSample(), query: "cafe")
        #expect(model.sections.map(\.title) == ["Sun, 25 Oct", "Today · Tue, 20 Oct", "Sat, 17 Oct"])
        #expect(model.sections.map(\.figuresText) == ["−₹350.00", "−₹320.00", "−₹410.00"])
        #expect(model.sections.map(\.isUpcoming) == [true, false, false])
        #expect(model.sections.first?.accessibilityLabel == "Upcoming, Sun, 25 Oct, −₹350.00")
        #expect(model.sections.last?.accessibilityLabel == "Sat, 17 Oct, −₹410.00")
    }

    @Test("Rows: payee title, category and account, no balance and no Upcoming badge (D120.1, D233.3)")
    func rows() throws {
        let model = model(try cafeSample(), query: "cafe")
        let upcoming = try #require(model.sections.first?.rows.first)
        #expect(upcoming.title == "Copper Cup Cafe")
        #expect(upcoming.subtitle == "Coffee Runs · Everyday Savings · 25 Oct")
        #expect(upcoming.isUpcoming == false)
        #expect(upcoming.balanceText.isEmpty)
        let card = try #require(model.sections.last?.rows.first)
        #expect(card.subtitle == "Coffee Runs · Rewards Card")
        #expect(card.compactAmountText == "−₹410.00")
        #expect(card.amountTone == .negative)
        #expect(card.accessibilityLabel == "Copper Cup Cafe, −₹410.00, Coffee Runs · Rewards Card")
    }

    @Test("S68, S93 (D173.9): transfers only show the amount moved; rows read from the sending side")
    func transfersOnly() throws {
        let cross = F.transfer(1_000, on: F.date(2026, 10, 16), to: F.usdID, received: 12)
        let same = F.transfer(2_500, on: F.date(2026, 10, 16, 9), to: F.walletID)
        let model = model(try repository([cross, same]), query: "type:transfer")
        let line = try #require(model.summary?.lines.first)
        #expect(line.incomeText == nil)
        #expect(line.movedText == "₹3,500.00")
        #expect(model.summary?.movedTitle == "Moved between your accounts")
        let rows = try #require(model.sections.first?.rows)
        #expect(rows.map(\.title) == ["To USD Wallet", "To Corner Wallet"])
        #expect(rows.map(\.subtitle) == ["Transfer · $12.00", "Transfer"])
        #expect(rows.first?.compactAmountText == "⇄₹1,000.00")
        #expect(rows.first?.amountTone == .transfer)
        #expect(model.sections.first?.figuresText == "₹3,500.00 moved")
    }

    @Test("S69 (D25): in one account, a received transfer is +$12.00 from the other account")
    func scopedTransfer() throws {
        let cross = F.transfer(1_000, on: F.date(2026, 10, 16), to: F.usdID, received: 12)
        let model = model(try repository([cross]), query: "type:transfer", accountID: F.usdID)
        let row = try #require(model.sections.first?.rows.first)
        #expect(row.title == "From Everyday Savings")
        #expect(row.subtitle == "Transfer · ₹1,000.00")
        #expect(row.compactAmountText == "+$12.00")
        #expect(model.summary?.lines.first?.movedText == "$12.00")
    }

    @Test("S6: transfers never change Income, Expenses or Net; mixed currencies stay apart, INR first")
    func mixedTotals() throws {
        let pay = F.income(5_000, on: F.date(2026, 10, 12), category: Self.salary.id)
        let spend = cafe(3_200, 12)
        let move = F.transfer(1_000, on: F.date(2026, 10, 12, 18))
        let usd = F.expense(15, on: F.date(2026, 10, 12), account: F.usdID)
        let model = model(try repository([pay, spend, move, usd]))
        let lines = try #require(model.summary?.lines)
        #expect(model.summary?.countText == "4 results")
        #expect(lines.map(\.currencyCode) == ["INR", "USD"])
        #expect(lines.map(\.incomeText) == ["₹5,000.00", "$0.00"])
        #expect(lines.map(\.expensesText) == ["₹3,200.00", "$15.00"])
        #expect(lines.map(\.netText) == ["+₹1,800.00", "−$15.00"])
        #expect(model.sections.first?.figuresText == "+₹1,800.00 · −$15.00")
    }

    @Test("S65 (D111): a currency with only a transfer that day reads “moved”")
    func mixedDay() throws {
        let spend = cafe(1_200, 12)
        let move = F.transfer(50, on: F.date(2026, 10, 12), from: F.usdID, to: F.savingsID, received: 4_100)
        let model = model(try repository([spend, move]))
        #expect(model.sections.first?.figuresText == "−₹1,200.00 · $50.00 moved")
    }

    @Test("S18: a malformed date shows the Use YYYY-MM-DD hint and the rest still searches")
    func hint() throws {
        let model = model(try cafeSample(), query: "after:2026-13-45 cafe")
        #expect(model.hints == ["Use YYYY-MM-DD"])
        #expect(model.summary?.countText == "3 results")
        model.query = "cafe"
        model.load()
        #expect(model.hints.isEmpty)
    }

    @Test("S22, S5 (D320.4, D321): no results is the empty state alone; Clear Search brings the full list back")
    func noResults() throws {
        let model = model(try cafeSample(), query: "lantern tea house")
        #expect(model.isNoResults)
        #expect(model.noResultsTitle == "No Results for “lantern tea house”")
        #expect(
            model.noResultsMessage
                == "Check the spelling or try fewer words. Search looks at description, category, payee, tag and notes."
        )
        #expect(model.clearSearchTitle == "Clear Search")
        // D321: only the empty state shows; no “0 results” count and no zero totals.
        #expect(model.summary == nil)
        #expect(model.sections.isEmpty)
        #expect(model.upcomingNote == nil)
        model.clear()
        #expect(model.query.isEmpty)
        #expect(!model.isNoResults)
        #expect(model.summary?.countText == "3 results")
    }

    @Test("The scope bar is the same filter as type: (All, Expenses, Income, Transfers)")
    func scope() throws {
        let pay = F.income(5_000, on: F.date(2026, 10, 12), category: Self.salary.id)
        let model = model(try repository([pay, cafe(100, 12)]))
        model.scope = .income
        model.load()
        #expect(model.summary?.countText == "1 result")
        #expect(model.sections.first?.rows.map(\.title) == ["Income"])
        #expect(SearchScopeOption.allCases.map(\.title) == ["All", "Expenses", "Income", "Transfers"])
    }

    @Test("S89–S92 (D134): the note's plural, and no note without upcoming matches")
    func upcomingNote() throws {
        let model = model(try repository([cafe(350, 25), cafe(120, 28), cafe(90, 18)]), query: "cafe")
        #expect(model.upcomingNote == "2 upcoming matches are listed but not counted.")
        model.query = "cafe before:2026-10-20"
        model.load()
        #expect(model.upcomingNote == nil)
        #expect(!model.hasUpcoming)
    }

    @Test("D320.5: an empty store with no query shows No Transactions, not No Results")
    func emptyStore() throws {
        let model = model(try repository([]))
        #expect(!model.isNoResults)
        #expect(model.isEmptyLedger)
        #expect(model.summary == nil)
        #expect(model.emptyTitle == "No Transactions")
        #expect(model.emptyMessage == "Transactions you add will appear here.")
    }

    @Test("A no-results scope shows the empty state alone too, with no count or totals (D321)")
    func noResultsScope() throws {
        let model = model(try cafeSample())
        model.scope = .transfers
        model.load()
        #expect(model.isNoResults)
        #expect(model.summary == nil)
        #expect(model.sections.isEmpty)
    }

    @Test("NB6: VoiceOver reads each currency's name, not its code, in the totals")
    func spokenCurrency() throws {
        let usd = F.expense(15, on: F.date(2026, 10, 12), account: F.usdID)
        let move = F.transfer(50, on: F.date(2026, 10, 12), from: F.usdID, to: F.savingsID, received: 4_100)
        let model = model(try repository([cafe(320, 20), usd]))
        let lines = try #require(model.summary?.lines)
        let inr = Locale(identifier: "en_IN").localizedString(forCurrencyCode: "INR") ?? "INR"
        let dollar = Locale(identifier: "en_IN").localizedString(forCurrencyCode: "USD") ?? "USD"
        #expect(inr != "INR")
        #expect(lines.first?.accessibilityLabel == "\(inr): Income ₹0.00, Expenses ₹320.00, Net −₹320.00")
        #expect(lines.last?.accessibilityLabel == "\(dollar): Income $0.00, Expenses $15.00, Net −$15.00")
        #expect(lines.first?.currencyCode == "INR", "The card still shows the code")
        let moved = self.model(try repository([move]), query: "type:transfer", accountID: F.usdID)
        #expect(moved.summary?.lines.first?.accessibilityLabel == "\(dollar): Moved between your accounts $50.00")
    }

    @Test("NB5: the scope bar and summary labels are search's own entries, with the same English")
    func contextLabels() throws {
        let model = model(try cafeSample(), query: "cafe")
        let summary = try #require(model.summary)
        #expect(summary.incomeTitle == "Income")
        #expect(summary.expensesTitle == "Expenses")
        #expect(SearchScopeOption.income.title == "Income")
        #expect(SearchScopeOption.expenses.title == "Expenses")
    }

    @Test("NB2: the store is read once; typing and the scope bar search that copy in memory")
    func readsOnce() throws {
        let repository = try cafeSample()
        let counting = CountingSearch(DefaultSearchTransactionsUseCase(repository: repository))
        let updates = LedgerUpdates()
        let model = searchModel(counting, updates: updates)
        model.load()
        for text in ["c", "ca", "caf", "cafe", "cafe before:2026-10-20", ""] {
            model.query = text
            model.load()
        }
        model.scope = .expenses
        model.load()
        model.load()
        #expect(counting.reads == 1)
        #expect(model.summary?.countText == "3 results")
        model.query = "cafe"
        model.load()
        let fresh = self.model(repository, query: "cafe")
        fresh.scope = .expenses
        fresh.load()
        #expect(model.sections == fresh.sections, "Reused rows match freshly built ones")
        #expect(model.summary == fresh.summary)
    }

    @Test("NB2: a restore moves the shared signal on, so the next search reads the store again, once")
    func rereadsOnChange() throws {
        let repository = try cafeSample()
        let counting = CountingSearch(DefaultSearchTransactionsUseCase(repository: repository))
        let updates = LedgerUpdates()
        let model = searchModel(counting, updates: updates)
        model.query = "cafe"
        model.load()
        try repository.saveTransaction(cafe(90, 19))
        model.load()
        #expect(model.summary?.countText == "3 results", "No signal yet, so the kept copy is searched")
        updates.ledgerReplaced()
        model.load()
        model.load()
        #expect(counting.reads == 2)
        #expect(model.summary?.countText == "4 results")
    }

    @Test("NB6: saving from a result's edit sheet reloads the results exactly once")
    func saveReloadsOnce() throws {
        let repository = try cafeSample()
        let counting = CountingSearch(DefaultSearchTransactionsUseCase(repository: repository))
        let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        let feature = TransactionsFeature(
            useCases: useCases,
            search: counting,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
        let history = feature.makeUndoHistory()
        let model = try #require(feature.makeSearch())
        model.query = "cafe"
        model.load()
        let row = try #require(model.sections.last?.rows.first)
        let form = feature.makeForm(.edit(row.id))
        form.note = "Oat milk"
        let change = try #require(form.save())
        // The sheet records the change, which moves the shared signal on; the screen reloads on that signal,
        // and any other caller in the same pass finds nothing new to read.
        history.record(change)
        model.load()
        model.load()
        #expect(counting.reads == 2, "One read on open, one after the save")
        model.query = "oat milk"
        model.load()
        #expect(counting.reads == 2)
        #expect(model.summary?.countText == "1 result")
    }

    @Test("TransactionsFeature makes a search screen only when search is wired in")
    func feature() throws {
        let repository = try cafeSample()
        let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        #expect(TransactionsFeature(useCases: useCases).makeSearch() == nil)
        let feature = TransactionsFeature(
            useCases: useCases,
            search: DefaultSearchTransactionsUseCase(repository: repository),
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
        #expect(feature.hasSearch)
        let model = try #require(feature.makeSearch())
        model.query = "cafe"
        model.load()
        #expect(model.summary?.countText == "3 results")
    }

    @Test("D320.6: a read failure shows Couldn’t Load Transactions and Try again., and no stale results")
    func failure() throws {
        let model = TransactionSearchViewModel(
            search: FailingSearch(),
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
            defaultCurrency: "INR",
        )
        model.query = "cafe"
        model.load()
        #expect(model.failure == SearchFailure(title: "Couldn’t Load Transactions", message: "Try again."))
        #expect(model.sections.isEmpty)
        #expect(model.summary == nil)
        #expect(!model.isNoResults)
        #expect(!model.isEmptyLedger)
    }

    private func searchModel(_ search: any SearchTransactionsUseCase, updates: LedgerUpdates)
        -> TransactionSearchViewModel
    {
        TransactionSearchViewModel(
            search: search,
            updates: updates,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
            defaultCurrency: "INR",
        )
    }
}

/// Counts the store reads behind a real search use case.
@MainActor
private final class CountingSearch: SearchTransactionsUseCase {
    private let base: any SearchTransactionsUseCase
    private(set) var reads = 0

    init(_ base: any SearchTransactionsUseCase) {
        self.base = base
    }

    func read() throws -> TransactionSearchSnapshot {
        reads += 1
        return try base.read()
    }
}

@MainActor
private struct FailingSearch: SearchTransactionsUseCase {
    struct Failure: Error {}

    func read() throws -> TransactionSearchSnapshot {
        throw Failure()
    }
}
