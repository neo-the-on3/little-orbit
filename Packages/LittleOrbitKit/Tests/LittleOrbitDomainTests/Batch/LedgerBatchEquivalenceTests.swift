import Foundation
import LittleOrbitDomain
import Testing

/// #285: a batch edit gives what the row-by-row saves gave, the same ledger or the same first error, including the
/// cases where the order of the rows matters (Tech Architect's condition on 6435113427).
@Suite("Batch edit of stored transactions: the same as row by row (#285)")
struct LedgerBatchEquivalenceTests {
    typealias B = BatchFixture  // swiftlint:disable:this type_name
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias R = RefundFixture  // swiftlint:disable:this type_name

    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        /// Whether the row-by-row saves accept it, so each case is known to test what its name says.
        let succeeds: Bool
        let rows: @Sendable (B.Ledger) -> [Transaction]
        var testDescription: String { name }
    }

    static func edit(_ row: Transaction, _ change: (inout Transaction) -> Void) -> Transaction {
        var row = row
        change(&row)
        return row
    }

    static let cases: [Case] = [
        Case(name: "An original's category, then its refund's", succeeds: true) { ledger in
            [
                edit(ledger.expense) { $0.categoryID = R.diningID },
                edit(ledger.refund) { $0.categoryID = R.diningID },
            ]
        },
        Case(name: "An original's category alone: its refund follows (D33.4)", succeeds: true) { ledger in
            [edit(ledger.expense) { $0.categoryID = R.shoppingID }]
        },
        Case(name: "A refund's category before its original's", succeeds: false) { ledger in
            [
                edit(ledger.refund) { $0.categoryID = R.diningID },
                edit(ledger.expense) { $0.categoryID = R.diningID },
            ]
        },
        Case(name: "An original below its refunds", succeeds: false) { ledger in
            [edit(ledger.expense) { $0.amount = 1_000 }]
        },
        Case(name: "A refund raised, then its original raised more", succeeds: false) { ledger in
            [
                edit(ledger.refund) { $0.amount = 6_000 },
                edit(ledger.expense) { $0.amount = 8_000 },
            ]
        },
        Case(name: "An original raised, then its refund raised", succeeds: true) { ledger in
            [
                edit(ledger.expense) { $0.amount = 8_000 },
                edit(ledger.refund) { $0.amount = 6_000 },
            ]
        },
        Case(name: "An original moved to another currency, with its refund still in INR", succeeds: false) { ledger in
            [edit(ledger.expense) { $0.accountID = F.usdID }]
        },
        Case(name: "Both moved to another INR account, the refund first", succeeds: true) { ledger in
            [
                edit(ledger.refund) { $0.accountID = F.walletID },
                edit(ledger.expense) { $0.accountID = F.walletID },
            ]
        },
        Case(name: "A split row's details", succeeds: true) { ledger in
            [edit(ledger.split) { $0.details = "Weekly shop" }]
        },
        Case(name: "A split row's amount", succeeds: false) { ledger in
            [edit(ledger.split) { $0.amount = 1_500 }]
        },
        Case(name: "A split row's category", succeeds: false) { ledger in
            [edit(ledger.split) { $0.categoryID = R.groceriesID }]
        },
        Case(name: "A deleted row, after a good one", succeeds: false) { ledger in
            [
                edit(ledger.dining) { $0.details = "Lunch" },
                edit(ledger.deleted) { $0.details = "Gone" },
            ]
        },
        Case(name: "A transfer's amount and accounts", succeeds: true) { ledger in
            let moved = edit(ledger.transfer) {
                $0.amount = 900
                $0.accountID = F.walletID
                $0.transferAccountID = F.savingsID
            }
            return [moved]
        },
        Case(name: "A transfer to another currency without the amount received", succeeds: false) { ledger in
            [edit(ledger.transfer) { $0.transferAccountID = F.usdID }]
        },
        Case(name: "An income given an expense category", succeeds: false) { ledger in
            [edit(ledger.income) { $0.categoryID = R.groceriesID }]
        },
        Case(name: "The same row twice: the second wins", succeeds: true) { ledger in
            [
                edit(ledger.dining) { $0.details = "First" },
                edit(ledger.dining) {
                    $0.details = "Second"
                    $0.amount = 3_100
                },
            ]
        },
        Case(name: "Every kind at once, all accepted", succeeds: true) { ledger in
            [
                edit(ledger.expense) { $0.date = F.date(2026, 10, 9) },
                edit(ledger.dining) { $0.categoryID = R.shoppingID },
                edit(ledger.split) { $0.details = "Split" },
                edit(ledger.transfer) { $0.amount = 650 },
                edit(ledger.income) { $0.amount = 95_000 },
                edit(ledger.refund) { $0.details = "Returned" },
            ]
        },
        Case(name: "A bad row in the middle stops the batch there", succeeds: false) { ledger in
            [
                edit(ledger.dining) { $0.details = "Before" },
                edit(ledger.income) { $0.amount = -5 },
                edit(ledger.transfer) { $0.amount = 650 },
            ]
        },
    ]

    @Test("The same ledger or the same first error as row by row", arguments: cases)
    func fixture(_ testCase: Case) throws {
        let ledger = try B.ledger()
        let rows = testCase.rows(ledger)
        let folded = B.folded(rows, in: ledger.snapshot)
        #expect(folded.isSuccess == testCase.succeeds, "\(folded)")
        #expect(B.batched(rows, in: ledger.snapshot) == folded)
    }

    @Test("The earlier versions are the rows', then the refunds that followed, as save(_:) records them")
    func previousVersions() throws {
        let ledger = try B.ledger()
        let rows = [
            Self.edit(ledger.dining) { $0.details = "Lunch" },
            Self.edit(ledger.expense) { $0.categoryID = R.shoppingID },
        ]
        let result = try LedgerBook.updatingTransactions(rows, in: ledger.snapshot, now: B.now)
        #expect(result.previous == [ledger.dining, ledger.expense, ledger.refund])
        #expect(result.changedIDs == [ledger.dining.id, ledger.expense.id, ledger.refund.id])
        let refund = try #require(result.snapshot.transaction(ledger.refund.id))
        #expect(refund.categoryID == R.shoppingID)
    }

    @Test("Progress every 64 rows and at the end")
    func progress() async throws {
        let ledger = try B.ledger()
        let rows = (0..<200).map { index in Self.edit(ledger.dining) { $0.details = "Edit \(index)" } }
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        _ = try LedgerBook.updatingTransactions(rows, in: ledger.snapshot, now: B.now) { continuation.yield($0) }
        continuation.finish()
        var reported: [Int] = []
        for await done in stream {
            reported.append(done)
        }
        #expect(reported == [64, 128, 192, 200])
    }

    @MainActor
    @Test("A cancelled batch stops at its next report and changes nothing")
    func cancelled() async throws {
        let ledger = try B.ledger()
        let rows = (0..<200).map { index in Self.edit(ledger.dining) { $0.details = "Edit \(index)" } }
        let snapshot = ledger.snapshot
        let task = Task { try LedgerBook.updatingTransactions(rows, in: snapshot, now: B.now) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
