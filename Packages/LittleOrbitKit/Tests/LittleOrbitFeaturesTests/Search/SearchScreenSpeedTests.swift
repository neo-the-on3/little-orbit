import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// #28's criterion, results in under 500 ms at 10,000 transactions (#187, S25), for the whole step the screen
/// runs: searching the kept copy and building its rows, day headers, summary and table. Also a save while the
/// list is unfiltered (Tech Architect #188 NB1) and a change of the table's sort. Debug builds on CI are slower
/// than the app's release build, so passing here leaves room; Tester's timing in the Mac app is the device check.
/// All names and amounts are made up.
@MainActor
@Suite("Search screen speed")
struct SearchScreenSpeedTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    static let transactionCount = 10_000
    static let bound = Duration.milliseconds(500)

    /// The store as a snapshot the test can change, as a save would.
    @MainActor
    final class Store: SearchTransactionsUseCase {
        var snapshot: TransactionSearchSnapshot
        private(set) var reads = 0

        init(_ snapshot: TransactionSearchSnapshot) {
            self.snapshot = snapshot
        }

        func read() throws -> TransactionSearchSnapshot {
            reads += 1
            return snapshot
        }
    }

    /// 10,000 transactions over three years in three accounts and two currencies, with categories, payees,
    /// details and notes.
    static func snapshot() -> TransactionSearchSnapshot {
        var seed: UInt64 = 187
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        let categories =
            (0..<40).map { TransactionCategory(name: "Category \($0)") } + [TransactionCategory(name: "Coffee Runs")]
        let payees = (0..<300).map { Payee(name: "Payee \($0)") } + [Payee(name: "Copper Cup Cafe")]
        let details = ["Lunch", "Coffee with team", "Weekly shop", "Fuel", nil, "Café visit"]
        let start = F.date(2023, 11, 1)
        let transactions = (0..<transactionCount)
            .map { index -> Transaction in
                let date = start.addingTimeInterval(Double(next(1_100 * 86_400)))
                let amount = Decimal(next(500_000)) / 100
                let pick = next(100)
                if pick < 8 {
                    return F.transfer(amount, on: date, to: pick < 2 ? F.usdID : F.walletID)
                }
                var transaction =
                    pick < 18
                    ? F.income(amount, on: date)
                    : F.expense(amount, on: date, account: pick < 25 ? F.usdID : F.savingsID)
                transaction.categoryID = categories[next(categories.count)].id
                transaction.payeeID = next(4) == 0 ? nil : payees[next(payees.count)].id
                transaction.details = details[index % details.count]
                transaction.note = index % 7 == 0 ? "Paid by card \(index)" : nil
                return transaction
            }
        return TransactionSearchSnapshot(
            ledger: TransactionLedger(
                accounts: F.accounts(),
                transactions: transactions,
                categories: categories,
                payees: payees,
            ),
            tags: [],
        )
    }

    private func model(_ store: Store, updates: LedgerUpdates) -> TransactionSearchViewModel {
        TransactionSearchViewModel(
            search: store,
            exporting: DefaultExportSearchResultsUseCase(),
            updates: updates,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
            defaultCurrency: "INR",
        )
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(Double(duration.components.seconds) * 1e3 + Double(duration.components.attoseconds) / 1e15)
    }

    @Test("S25: typing “coffee” letter by letter, each update over 10,000 transactions is under 500 ms")
    func typing() {
        let store = Store(Self.snapshot())
        let model = model(store, updates: LedgerUpdates())
        model.load()
        #expect(model.summary?.countText == "10,000 results")
        let clock = ContinuousClock()
        for text in ["c", "co", "cof", "coff", "coffe", "coffee", "category:Coffee year:2025", "zzzz", ""] {
            model.query = text
            let elapsed = clock.measure { model.load() }
            print("Search screen speed: “\(text)” in \(Self.milliseconds(elapsed)) ms")
            #expect(elapsed < Self.bound, "“\(text)” took \(elapsed)")
        }
        #expect(store.reads == 1)
    }

    @Test("NB1: a save while the list of 10,000 is unfiltered updates in under 500 ms, rows matching a fresh build")
    func saveWhileUnfiltered() throws {
        let store = Store(Self.snapshot())
        let updates = LedgerUpdates()
        let model = model(store, updates: updates)
        model.load()
        let clock = ContinuousClock()
        var edited = store.snapshot
        let index = try #require(edited.ledger.transactions.firstIndex { $0.type == .expense })
        edited.ledger.transactions[index].details = "Oat milk refill"
        edited.ledger.transactions.append(F.expense(42, on: F.date(2026, 10, 19), details: "Lantern tea"))
        store.snapshot = edited
        updates.ledgerReplaced()

        let elapsed = clock.measure { model.load() }
        print("Search screen speed: save while unfiltered in \(Self.milliseconds(elapsed)) ms")
        #expect(elapsed < Self.bound, "The save took \(elapsed)")
        #expect(store.reads == 2)
        #expect(model.summary?.countText == "10,001 results")

        let fresh = self.model(store, updates: updates)
        fresh.load()
        #expect(model.sections == fresh.sections, "Carried rows match a fresh build")
        #expect(model.tableSections == fresh.tableSections, "Carried table cells match a fresh build")
        let titles = model.sections.flatMap(\.rows).map(\.title)
        #expect(titles.contains("Lantern tea"))
    }

    @Test("Changing the table's sort over 10,000 results takes under 500 ms (S63)")
    func sorting() {
        let model = model(Store(Self.snapshot()), updates: LedgerUpdates())
        model.load()
        let clock = ContinuousClock()
        for order in [
            KeyPathComparator(\SearchTableRow.amount, order: .forward),
            KeyPathComparator(\SearchTableRow.descriptionText, order: .forward),
            KeyPathComparator(\SearchTableRow.payee, order: .forward),
            KeyPathComparator(\SearchTableRow.date, order: .forward),
        ] {
            let elapsed = clock.measure { model.sortOrder = [order] }
            print("Search screen speed: sort in \(Self.milliseconds(elapsed)) ms")
            #expect(elapsed < Self.bound)
        }
        #expect(model.tableSections.flatMap(\.rows).count == Self.transactionCount)
    }
}
