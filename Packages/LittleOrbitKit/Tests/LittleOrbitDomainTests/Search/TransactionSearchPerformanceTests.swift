import Foundation
import LittleOrbitDomain
import Testing

/// #28's speed criterion (500 ms at 10,000 transactions) for the in-memory search step that runs on each
/// keystroke. The bound is generous because `swift test` builds for debugging and CI machines vary; Tester's
/// timing in the Mac app is the real check (S25). All names and amounts are made up.
@Suite("Search speed")
struct TransactionSearchPerformanceTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    static let transactionCount = 10_000
    static let today = F.day(2026, 10, 21)
    /// The search step for one query, in a debug build. Release builds are several times faster.
    static let bound = Duration.seconds(2)

    /// 10,000 transactions over three years: expenses, income, refunds and transfers, with categories, payees,
    /// tags, details and notes, a few in another currency.
    static func ledger() -> TransactionSearchLedger {
        var generator = SplitMix(seed: 28)
        let categories =
            (0..<40).map { TransactionCategory(name: "Category \($0)") } + [
                TransactionCategory(name: "Groceries"), TransactionCategory(name: "Coffee Runs"),
                TransactionCategory(name: "Salary", kind: .income),
            ]
        let payees =
            (0..<300).map { Payee(name: "Payee \($0)") } + [
                Payee(name: "Copper Cup Cafe"), Payee(name: "Café Noir"), Payee(name: "Corner Bakery"),
            ]
        let tags = (0..<20).map { F.tag("tag\($0)") }
        let details = ["Lunch", "Coffee with team", "Weekly shop", "Fuel", "Rent", nil, nil, "Café visit"]
        let start = F.date(2023, 11, 1)
        let transactions = (0..<Self.transactionCount)
            .map { index -> Transaction in
                let date = start.addingTimeInterval(Double(generator.next(below: 1_100 * 86_400)))
                let amount = Decimal(generator.next(below: 500_000)) / 100
                let pick = generator.next(below: 100)
                var transaction: Transaction
                switch pick {
                case 0..<8:
                    transaction = F.transfer(amount, on: date, to: pick < 2 ? F.usdID : F.walletID)
                case 8..<18:
                    transaction = F.income(amount, on: date)
                    transaction.isRefund = pick < 10
                default:
                    transaction = F.expense(amount, on: date, account: pick < 25 ? F.usdID : F.savingsID)
                }
                if transaction.type != .transfer {
                    transaction.categoryID = categories[generator.next(below: categories.count)].id
                    transaction.payeeID =
                        generator.next(below: 4) == 0 ? nil : payees[generator.next(below: payees.count)].id
                    transaction.details = details[index % details.count]
                    transaction.note = index % 7 == 0 ? "Paid by card \(index)" : nil
                    transaction.tagIDs = index % 5 == 0 ? [tags[index % tags.count].id] : []
                }
                return transaction
            }
        return TransactionSearchLedger(
            accounts: F.accounts,
            transactions: transactions,
            categories: categories,
            payees: payees,
            tags: tags,
        )
    }

    /// The fastest of three runs, so one slow scheduling slot doesn't decide the result.
    static func time(_ text: String, in ledger: TransactionSearchLedger) -> (Duration, TransactionSearchResult) {
        let query = TransactionSearchQuery.parse(text)
        let clock = ContinuousClock()
        var best = Duration.seconds(1_000)
        var result = TransactionSearchResult()
        for _ in 0..<3 {
            let elapsed = clock.measure {
                result = TransactionSearch.run(query, in: ledger, today: Self.today, defaultCurrency: "INR")
            }
            best = min(best, elapsed)
        }
        return (best, result)
    }

    static let queries = ["", "c", "co", "cof", "coffee", "cafe", "category:Groceries year:2026", "zzzz"]

    /// One test, so the queries run one after another and their timings don't share the CPU.
    @Test("S25: the in-memory search over 10,000 transactions stays within the bound for each query")
    func searchStep() {
        let ledger = Self.ledger()
        for text in Self.queries {
            let (elapsed, result) = Self.time(text, in: ledger)
            let milliseconds = Double(elapsed.components.seconds) * 1e3 + Double(elapsed.components.attoseconds) / 1e15
            print(
                "Search speed: “\(text)” matched \(result.count) of \(Self.transactionCount) in \(Int(milliseconds)) ms"
            )
            #expect(elapsed < Self.bound, "“\(text)” took \(elapsed)")
        }
        #expect(Self.time("", in: ledger).1.count == Self.transactionCount)
    }
}

/// A small seeded generator, so the 10,000 transactions are the same on every run.
private struct SplitMix {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next(below bound: Int) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Int(value % UInt64(bound))
    }
}
