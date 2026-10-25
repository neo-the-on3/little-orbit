import Foundation
import LittleOrbitDomain
import Testing

/// Matching, totals and day figures for #28 search. All names and amounts are made up.
@Suite("Transaction search")
struct TransactionSearchTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    static let dining = TransactionCategory(name: "Dining")
    static let salary = TransactionCategory(name: "Salary", kind: .income)
    static let electronics = TransactionCategory(name: "Electronics")
    static let copperCup = Payee(name: "Copper Cup Cafe")
    static let cafeNoir = Payee(name: "Café Noir")
    static let goa = TransactionFixture.tag("goa")
    static let today = F.day(2026, 10, 21)

    private func ledger(_ transactions: [Transaction], accounts: [Account] = F.accounts) -> TransactionSearchLedger {
        TransactionSearchLedger(
            accounts: accounts,
            transactions: transactions,
            categories: [Self.dining, Self.salary, Self.electronics],
            payees: [Self.copperCup, Self.cafeNoir],
            tags: [Self.goa],
        )
    }

    private func run(
        _ text: String,
        _ transactions: [Transaction],
        filter: TransactionSearchFilter = TransactionSearchFilter(),
        accounts: [Account] = F.accounts,
    ) -> TransactionSearchResult {
        TransactionSearch.run(
            TransactionSearchQuery.parse(text),
            filter: filter,
            in: ledger(transactions, accounts: accounts),
            today: Self.today,
            defaultCurrency: "INR",
        )
    }

    private func ids(_ result: TransactionSearchResult) -> Set<UUID> {
        Set(result.days.flatMap(\.matches).map(\.transaction.id))
    }

    private func expense(
        _ amount: Decimal,
        _ day: Int,
        month: Int = 10,
        account: UUID = F.savingsID,
        category: TransactionCategory? = dining,
        payee: Payee? = nil,
        details: String? = nil,
        note: String? = nil,
        tags: [UUID] = [],
    ) -> Transaction {
        var transaction = F.expense(amount, on: F.date(2026, month, day), account: account)
        transaction.categoryID = category?.id
        transaction.payeeID = payee?.id
        transaction.details = details
        transaction.note = note
        transaction.tagIDs = tags
        return transaction
    }

    // MARK: - Matching

    @Test("AC 1: plain words match description, category, payee, tag and notes")
    func fields() {
        let byDetails = expense(10, 1, category: nil, details: "Weekly groceries")
        let byCategory = expense(20, 2)
        let byPayee = expense(30, 3, category: nil, payee: Self.copperCup)
        let byTag = expense(40, 4, category: nil, tags: [Self.goa.id])
        let byNote = expense(50, 5, category: nil, note: "birthday gift for Ravi")
        let all = [byDetails, byCategory, byPayee, byTag, byNote]
        #expect(ids(run("groceries", all)) == [byDetails.id])
        #expect(ids(run("dining", all)) == [byCategory.id])
        #expect(ids(run("copper", all)) == [byPayee.id])
        #expect(ids(run("GOA", all)) == [byTag.id])
        #expect(ids(run("ravi", all)) == [byNote.id])
    }

    @Test("Every word must match, each in any field")
    func allWords() {
        let match = expense(10, 1, payee: Self.copperCup)
        let other = expense(20, 2, category: nil, payee: Self.copperCup)
        #expect(ids(run("copper dining", [match, other])) == [match.id])
    }

    @Test("S23: matching ignores case and diacritics")
    func diacritics() {
        let noir = expense(10, 1, payee: Self.cafeNoir)
        #expect(ids(run("cafe", [noir])) == [noir.id])
        #expect(ids(run("CAFÉ", [noir])) == [noir.id])
        #expect(ids(run("noïr", [noir])) == [noir.id])
    }

    @Test("S24: Devanagari text and emoji are found")
    func scripts() {
        let grocer = expense(10, 1, category: nil, details: "दैनिक किराना")
        let coffee = expense(20, 2, category: nil, note: "morning ☕️")
        #expect(ids(run("किराना", [grocer, coffee])) == [grocer.id])
        #expect(ids(run("☕️", [grocer, coffee])) == [coffee.id])
    }

    @Test("S19: foo:bar is plain text and finds a note containing it")
    func unknownOperatorText() {
        let note = expense(10, 1, category: nil, note: "ref foo:bar 12")
        #expect(ids(run("foo:bar", [note])) == [note.id])
    }

    @Test("AC 2: operators all apply; quoted multi-word values work")
    func operators() {
        let march = expense(100, 15, month: 3, payee: Self.copperCup)
        let marchOther = expense(100, 15, month: 3, category: Self.electronics, payee: Self.copperCup)
        let april = expense(100, 1, month: 4, payee: Self.copperCup)
        let all = [march, marchOther, april]
        #expect(
            ids(run("payee:\"Copper Cup Cafe\" category:Dining after:2026-03-01 before:2026-03-31", all)) == [march.id]
        )
        #expect(ids(run("tag:goa", [expense(1, 1, tags: [Self.goa.id]), march])).count == 1)
        #expect(ids(run("notes:gift", [expense(1, 1, note: "gift"), march])).count == 1)
        #expect(ids(run("year:2026", all)).count == 3)
        #expect(ids(run("year:2025", all)).isEmpty)
    }

    @Test("S12–S15: after: and before: include the given days; an inverted range finds nothing")
    func inclusiveDates() {
        let first = expense(1, 1)
        let last = expense(2, 31)
        let before = expense(3, 30, month: 9)
        let after = expense(4, 1, month: 11)
        let all = [first, last, before, after]
        #expect(ids(run("after:2026-10-01 before:2026-10-31", all)) == [first.id, last.id])
        #expect(ids(run("after:2026-10-01 before:2026-10-01", all)) == [first.id])
        #expect(ids(run("after:2026-10-31 before:2026-10-01", all)).isEmpty)
    }

    @Test("S16: dates use the day the transaction was entered in, not the device's zone")
    func entryZone() {
        let late = Transaction(
            type: .expense,
            amount: 10,
            date: F.date(2026, 10, 20, 23, 45),
            timeZoneID: F.india,
            accountID: F.savingsID,
        )
        #expect(ids(run("after:2026-10-20 before:2026-10-20", [late])) == [late.id])
    }

    @Test("type: and the scope filter pick the kind; a refund is an expense, never income (D46)")
    func types() {
        let spend = expense(100, 1)
        let pay = Transaction(
            type: .income,
            amount: 500,
            date: F.date(2026, 10, 2),
            timeZoneID: F.india,
            accountID: F.savingsID,
        )
        var refund = Transaction(
            type: .income,
            amount: 30,
            date: F.date(2026, 10, 3),
            timeZoneID: F.india,
            accountID: F.savingsID,
        )
        refund.isRefund = true
        let move = F.transfer(50, on: F.date(2026, 10, 4))
        let all = [spend, pay, refund, move]
        #expect(ids(run("type:expense", all)) == [spend.id, refund.id])
        #expect(ids(run("type:income", all)) == [pay.id])
        #expect(ids(run("type:transfer", all)) == [move.id])
        #expect(ids(run("", all, filter: TransactionSearchFilter(type: .income))) == [pay.id])
        #expect(ids(run("type:expense", all, filter: TransactionSearchFilter(type: .income))).isEmpty)
    }

    @Test("S26: hidden accounts are searched; deleted transactions and accounts are not")
    func visibility() {
        var accounts = F.accounts
        accounts[1].isHidden = true
        let hidden = expense(10, 1, account: F.walletID)
        var deleted = expense(20, 2)
        deleted.deletedAt = F.date(2026, 10, 3)
        let orphan = expense(30, 3, account: UUID())
        #expect(ids(run("", [hidden, deleted, orphan], accounts: accounts)) == [hidden.id])
    }

    @Test("S5: an empty query lists every transaction, newest day first")
    func emptyQuery() {
        let older = expense(10, 1)
        let newer = expense(20, 5)
        let result = run("", [older, newer])
        #expect(result.days.map(\.day) == [F.day(2026, 10, 5), F.day(2026, 10, 1)])
        #expect(result.count == 2)
    }

    // MARK: - Totals

    @Test("S6: transfers are listed and counted but never in Income, Expenses or Net")
    func totals() throws {
        let pay = Transaction(
            type: .income,
            amount: 5_000,
            date: F.date(2026, 10, 12),
            timeZoneID: F.india,
            accountID: F.savingsID,
        )
        let spend = expense(3_200, 12)
        let move = F.transfer(1_000, on: F.date(2026, 10, 12))
        let result = run("", [pay, spend, move])
        #expect(result.count == 3)
        let inr = try #require(result.totals.first)
        #expect(result.totals.count == 1)
        #expect(inr.currencyCode == "INR")
        #expect(inr.income == 5_000)
        #expect(inr.expenses == 3_200)
        #expect(inr.net == 1_800)
        #expect(inr.hasIncomeOrExpense)
    }

    @Test("S68: transfers only show the amount moved")
    func transfersOnly() throws {
        let moves = [1_000, 6_000, 15_000].enumerated()
            .map { index, amount in
                F.transfer(Decimal(amount), on: F.date(2026, 10, index + 1))
            }
        let inr = try #require(run("type:transfer", moves).totals.first)
        #expect(!inr.hasIncomeOrExpense)
        #expect(inr.moved == 22_000)
        #expect(inr.net == 0)
    }

    @Test("S9: totals per currency, never summed, default currency first")
    func perCurrency() {
        let usd = expense(15, 1, account: F.usdID)
        let inr = expense(1_200, 2)
        let yen = expense(500, 3, account: F.jpyID)
        let result = run("", [usd, inr, yen])
        #expect(result.totals.map(\.currencyCode) == ["INR", "JPY", "USD"])
        #expect(result.totals.map(\.expenses) == [1_200, 500, 15])
    }

    @Test("S37: a cross-currency transfer counts once, in the source currency at the amount sent")
    func crossCurrency() {
        let move = F.transfer(1_000, on: F.date(2026, 10, 9), to: F.usdID, received: 12)
        let result = run("type:transfer", [move])
        #expect(result.totals.map(\.currencyCode) == ["INR"])
        #expect(result.totals.first?.moved == 1_000)
        #expect(result.days.first?.matches.first?.accountID == F.savingsID)
        #expect(result.days.first?.matches.first?.effect == -1_000)
    }

    @Test("S38, S41 (D25): scoped to one account, a transfer uses that account's side")
    func accountScope() {
        let move = F.transfer(1_000, on: F.date(2026, 10, 9), to: F.usdID, received: 12)
        let spend = expense(40, 9, account: F.usdID)
        let other = expense(5, 9)
        let usd = run("", [move, spend, other], filter: TransactionSearchFilter(accountID: F.usdID))
        #expect(ids(usd) == [move.id, spend.id])
        #expect(usd.totals.map(\.currencyCode) == ["USD"])
        #expect(usd.totals.first?.expenses == 40)
        #expect(usd.totals.first?.income == 0)
        let received = usd.days.flatMap(\.matches).first { $0.transaction.id == move.id }
        #expect(received?.effect == 12)
        #expect(received?.currencyCode == "USD")
        let inr = run("type:transfer", [move], filter: TransactionSearchFilter(accountID: F.savingsID))
        #expect(inr.days.first?.matches.first?.effect == -1_000)
    }

    @Test("D31, S42–S44: a refund lowers Expenses and is never income")
    func refunds() {
        let spend = expense(1_000, 1, category: Self.electronics)
        var refund = Transaction(
            type: .income,
            amount: 300,
            date: F.date(2026, 10, 2),
            timeZoneID: F.india,
            accountID: F.savingsID,
        )
        refund.isRefund = true
        let both = run("", [spend, refund]).totals.first
        #expect(both?.expenses == 700)
        #expect(both?.income == 0)
        let alone = run("", [refund]).totals.first
        #expect(alone?.expenses == -300)
        #expect(alone?.hasIncomeOrExpense == true)
    }

    @Test("D47, D120.2: upcoming matches are listed and counted in the number, but in no total; today counts")
    func upcoming() throws {
        let today = expense(100, 21)
        let tomorrow = expense(350, 22)
        let laterMove = F.transfer(1_000, on: F.date(2026, 10, 25))
        let result = run("", [today, tomorrow, laterMove])
        #expect(result.count == 3)
        #expect(result.upcomingCount == 2)
        #expect(result.totals.map(\.expenses) == [100])
        #expect(result.totals.map(\.moved) == [0])
        #expect(result.days.map(\.isUpcoming) == [true, true, false])
        let upcomingDay = try #require(result.days.first { $0.day == F.day(2026, 10, 22) })
        #expect(upcomingDay.totals.first?.net == -350)
    }

    @Test("Everything upcoming: no counted totals at all")
    func onlyUpcoming() {
        let result = run("", [expense(350, 25)])
        #expect(result.totals.isEmpty)
        #expect(result.upcomingCount == 1)
    }

    // MARK: - Day figures

    @Test("S46–S49 (D56): a day's net leaves transfers out; a transfers-only day shows the amount moved")
    func dayFigures() throws {
        let salary = Transaction(
            type: .income,
            amount: 5_000,
            date: F.date(2026, 10, 12, 9),
            timeZoneID: F.india,
            accountID: F.savingsID,
        )
        let bean = expense(800, 12)
        let move12 = F.transfer(1_000, on: F.date(2026, 10, 12, 18))
        let move9 = F.transfer(2_000, on: F.date(2026, 10, 9))
        let in7 = Transaction(
            type: .income,
            amount: 800,
            date: F.date(2026, 10, 7),
            timeZoneID: F.india,
            accountID: F.savingsID,
        )
        let out7 = expense(800, 7)
        let move7 = F.transfer(300, on: F.date(2026, 10, 7))
        let result = run("", [salary, bean, move12, move9, in7, out7, move7])
        let days = Dictionary(uniqueKeysWithValues: result.days.map { ($0.day.day, $0) })
        let twelfth = try #require(days[12]?.totals.first)
        #expect(twelfth.net == 4_200)
        #expect(twelfth.hasIncomeOrExpense)
        #expect(days[12]?.matches.count == 3)
        let ninth = try #require(days[9]?.totals.first)
        #expect(!ninth.hasIncomeOrExpense)
        #expect(ninth.moved == 2_000)
        let seventh = try #require(days[7]?.totals.first)
        #expect(seventh.hasIncomeOrExpense)
        #expect(seventh.net == 0)
    }

    @Test("S65 (D111): a currency with only a transfer on a mixed day is its own moved figure")
    func mixedDay() {
        let spend = expense(1_200, 12)
        let move = F.transfer(50, on: F.date(2026, 10, 12), from: F.usdID, to: F.savingsID, received: 4_100)
        let day = run("", [spend, move]).days.first
        #expect(day?.totals.map(\.currencyCode) == ["INR", "USD"])
        #expect(day?.totals.map(\.hasIncomeOrExpense) == [true, false])
        #expect(day?.totals.last?.moved == 50)
    }

    @Test("Rows in a day are newest first")
    func rowOrder() {
        let morning = Transaction(
            type: .expense,
            amount: 1,
            date: F.date(2026, 10, 12, 9),
            timeZoneID: F.india,
            accountID: F.savingsID,
        )
        let evening = Transaction(
            type: .expense,
            amount: 2,
            date: F.date(2026, 10, 12, 20),
            timeZoneID: F.india,
            accountID: F.savingsID,
        )
        let result = run("", [morning, evening])
        #expect(result.days.first?.matches.map(\.transaction.id) == [evening.id, morning.id])
    }
}
