import Foundation
import Testing

@testable import LittleOrbitDomain

/// #340: the kept index finds exactly what the full pass over the ledger found (criterion 7), and each keystroke
/// over it stays well inside S25's 500 ms. All names and amounts are made up.
@Suite("Search index")
struct TransactionSearchIndexTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    static let today = TransactionSearchPerformanceTests.today

    /// The speed ledger with the cases ordering and matching can trip on: other time zones, rows sharing a time,
    /// deleted rows, a deleted category and account, and text with accents, Devanagari and emoji.
    static func ledger() -> TransactionSearchLedger {
        var ledger = TransactionSearchPerformanceTests.ledger(count: 3_000)
        let zones = ["America/Los_Angeles", "Pacific/Kiritimati", "UTC"]
        for index in ledger.transactions.indices {
            if index % 11 == 0 {
                ledger.transactions[index].timeZoneID = zones[index % zones.count]
            }
            if index % 13 == 1 {
                // The same time and creation time as the row before, so the id decides the order.
                ledger.transactions[index].date = ledger.transactions[index - 1].date
                ledger.transactions[index].createdAt = ledger.transactions[index - 1].createdAt
            }
            if index % 97 == 0 {
                ledger.transactions[index].deletedAt = F.date(2026, 1, 1)
            }
            switch index % 50 {
            case 3: ledger.transactions[index].details = "CAFÉ crème"
            case 4: ledger.transactions[index].details = "दूध और चाय"
            case 5: ledger.transactions[index].note = "Birthday 🎂 cake"
            case 6: ledger.transactions[index].details = "cafe\u{301} decomposed"
            default: break
            }
        }
        ledger.categories[0].deletedAt = F.date(2026, 2, 1)
        ledger.accounts[3].deletedAt = F.date(2026, 2, 1)
        ledger.transactions.append(F.expense(9, on: F.date(2026, 3, 3), account: F.jpyID))
        return ledger
    }

    static let queries = [
        "", "c", "co", "cof", "coffee", "cafe", "CAFÉ", "Café Noir", "\"copper cup\"", "payee:cafe", "payee:\"Corner\"",
        "category:groc year:2026", "category:\"Category 0\"", "tag:tag1", "tag:tag", "notes:card", "type:income",
        "type:expense paid", "after:2025-01-01 before:2025-06-30", "after:2026-10-20", "zzzz", "paid 7", "foo:bar",
        "after:bad lunch", "दूध", "🎂", "card 1", "year:2024 fuel",
    ]

    static let filters = [
        TransactionSearchFilter(),
        TransactionSearchFilter(type: .expense),
        TransactionSearchFilter(type: .income),
        TransactionSearchFilter(type: .transfer),
        TransactionSearchFilter(accountID: F.walletID),
        TransactionSearchFilter(type: .expense, accountID: F.usdID),
        TransactionSearchFilter(accountID: F.jpyID),
    ]

    @Test("Criterion 7: one kept index gives the full pass's result for every query and filter, in order")
    func sameAsFullPass() {
        let ledger = Self.ledger()
        let index = TransactionSearchIndex(ledger)
        var compared = 0
        for filter in Self.filters {
            for text in Self.queries {
                let query = TransactionSearchQuery.parse(text)
                let expected = ReferenceSearch.run(
                    query,
                    filter: filter,
                    in: ledger,
                    today: Self.today,
                    defaultCurrency: "INR",
                )
                let indexed = index.run(query, filter: filter, today: Self.today, defaultCurrency: "INR")
                #expect(indexed == expected, "“\(text)” with \(filter)")
                compared += 1
            }
        }
        #expect(compared == Self.queries.count * Self.filters.count)
        let all = index.run(TransactionSearchQuery(), today: Self.today, defaultCurrency: "INR")
        #expect(all.count > 2_900 && all.upcomingCount > 0, "The ledger lists most rows and some upcoming ones")
    }

    @Test("The one-off search and the snapshot's search give the same result as the kept index")
    func entryPointsAgree() {
        let ledger = Self.ledger()
        let index = TransactionSearchIndex(ledger)
        let snapshot = TransactionSearchSnapshot(
            ledger: TransactionLedger(
                accounts: ledger.accounts,
                transactions: ledger.transactions,
                categories: ledger.categories,
                payees: ledger.payees,
            ),
            tags: ledger.tags,
        )
        for text in ["", "cafe", "tag:tag1 lunch", "zzzz"] {
            let query = TransactionSearchQuery.parse(text)
            let kept = index.run(query, today: Self.today, defaultCurrency: "USD")
            #expect(TransactionSearch.run(query, in: ledger, today: Self.today, defaultCurrency: "USD") == kept)
            let filter = TransactionSearchFilter()
            #expect(snapshot.search(query, filter: filter, today: Self.today, defaultCurrency: "USD") == kept)
        }
    }

    @Test("Searching again after an edit, a rename and a delete matches a full pass over the changed ledger")
    func changedLedger() throws {
        var ledger = Self.ledger()
        let first = try #require(ledger.transactions.firstIndex { $0.deletedAt == nil && $0.type == .expense })
        ledger.transactions[first].details = "Oat milk refill"
        ledger.payees[0].name = "Payee Zero & Co."
        ledger.transactions[first + 1].deletedAt = F.date(2026, 5, 5)
        let index = TransactionSearchIndex(ledger)
        for text in ["oat", "zero", "payee", ""] {
            let query = TransactionSearchQuery.parse(text)
            let expected = ReferenceSearch.run(query, in: ledger, today: Self.today, defaultCurrency: "INR")
            #expect(index.run(query, today: Self.today, defaultCurrency: "INR") == expected, "“\(text)”")
        }
    }

    // MARK: - Speed guard (S25)

    /// The ledger size of PM's speed check (#340, 6486802598): twice S25's 10,000.
    static let speedCount = 20_000
    /// One keystroke's search over the kept index, in a debug build. It measures about 15–65 ms at 20,000 on a
    /// Linux box, so the bound leaves several times that for a slow CI machine.
    static let keystrokeBound = Duration.milliseconds(500)
    /// Making the index once per read of the store.
    static let indexBound = Duration.seconds(2)

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(Double(duration.components.seconds) * 1e3 + Double(duration.components.attoseconds) / 1e15)
    }

    @Test("S25 guard: typing “coffee”, “zzzz” and clearing at 20,000 transactions stay well inside 500 ms each")
    func keystrokesAtTwentyThousand() {
        let ledger = TransactionSearchPerformanceTests.ledger(count: Self.speedCount)
        let clock = ContinuousClock()
        var index: TransactionSearchIndex?
        let built = clock.measure { index = TransactionSearchIndex(ledger) }
        print("Search index: made for \(Self.speedCount) transactions in \(Self.milliseconds(built)) ms")
        #expect(built < Self.indexBound, "Making the index took \(built)")
        guard let index else {
            return
        }
        for text in ["c", "co", "cof", "coff", "coffe", "coffee", "", "zzzz", "cafe", "category:Groceries year:2026"] {
            let query = TransactionSearchQuery.parse(text)
            var result = TransactionSearchResult()
            // The fastest of three runs, so one slow scheduling slot doesn't decide it.
            var best = Duration.seconds(1_000)
            for _ in 0..<3 {
                let elapsed = clock.measure {
                    result = index.run(query, today: Self.today, defaultCurrency: "INR")
                }
                best = min(best, elapsed)
            }
            print("Search index: “\(text)” matched \(result.count) in \(Self.milliseconds(best)) ms")
            #expect(best < Self.keystrokeBound, "“\(text)” took \(best)")
        }
    }
}
