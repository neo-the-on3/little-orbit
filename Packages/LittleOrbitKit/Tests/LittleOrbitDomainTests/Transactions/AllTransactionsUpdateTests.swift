import Foundation
import LittleOrbitDomain
import Testing

/// #341: All Transactions applies a change to the rows it touched, rather than sorting every account's
/// transactions again. Each update must give exactly what a full build of the stored ledger gives. Made-up data.
@Suite("All Transactions list, updated in place (#341)")
struct AllTransactionsUpdateTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    private let build = BuildAllTransactions()
    private let today = TransactionFixture.day(2026, 10, 28)
    /// One copy: each read of `F.accounts` makes accounts with a new `createdAt`.
    private let accounts = TransactionFixture.accounts

    private let bakery = F.expense(8, on: F.date(2026, 10, 27), account: F.usdID)
    private let metro = F.expense(12, on: F.date(2026, 10, 28), account: F.savingsID)
    private let tea = F.expense(60, on: F.date(2026, 10, 26), account: F.walletID)
    private let move = F.transfer(100, on: F.date(2026, 10, 25), from: F.usdID, to: F.savingsID)

    /// The update from `before` to `after`, for `changed`, next to a full build of `after`.
    private func check(
        _ before: [Transaction],
        _ after: [Transaction],
        changed: Set<UUID>,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) {
        let previous = build(accounts: accounts, transactions: before, today: today)
        let updated = build.updating(
            previous,
            changed: changed,
            accounts: accounts,
            transactions: after,
            today: today,
        )
        #expect(
            updated == build(accounts: accounts, transactions: after, today: today),
            sourceLocation: sourceLocation,
        )
    }

    @Test("An edit that keeps its day, one that moves it to another day, and one that moves it to Upcoming")
    func edits() {
        let rows = [bakery, metro, tea, move]
        var amount = rows[1]
        amount.amount = 14
        check(rows, [rows[0], amount, rows[2], rows[3]], changed: [amount.id])
        var moved = rows[1]
        moved.date = F.date(2026, 10, 24)
        check(rows, [rows[0], moved, rows[2], rows[3]], changed: [moved.id])
        var later = rows[2]
        later.date = F.date(2026, 12, 2)
        check(rows, [rows[0], rows[1], later, rows[3]], changed: [later.id])
    }

    @Test("An add, a delete, a soft delete and a transfer moved to another account, each in place")
    func addsAndDeletes() {
        let rows = [bakery, metro, tea, move]
        let added = F.expense(5, on: F.date(2026, 10, 27, 18), account: F.walletID)
        check(rows, rows + [added], changed: [added.id])
        check(rows, [rows[0], rows[2], rows[3]], changed: [rows[1].id])
        var gone = rows[0]
        gone.deletedAt = F.date(2026, 10, 28)
        check(rows, [gone, rows[1], rows[2], rows[3]], changed: [gone.id])
        var transfer = rows[3]
        transfer.accountID = F.walletID
        check(rows, [rows[0], rows[1], rows[2], transfer], changed: [transfer.id])
    }

    @Test("Several changes at once, ties on one day keep their order, and an unknown id changes nothing")
    func severalAndTies() {
        let noon = F.date(2026, 10, 27, 12)
        let first = F.expense(1, on: noon, created: F.date(2026, 10, 27, 9))
        let second = F.expense(2, on: noon, created: F.date(2026, 10, 27, 10))
        let rows = [bakery, metro, first, second]
        let third = F.expense(3, on: noon, created: F.date(2026, 10, 27, 11))
        var earlier = second
        earlier.createdAt = F.date(2026, 10, 27, 8)
        check(rows, [rows[0], rows[1], first, earlier, third], changed: [earlier.id, third.id, rows[0].id])
        check(rows, rows, changed: [UUID()])
        check(rows, rows, changed: [])
    }

    @Test("A 2,000-row ledger, then 40 edits, adds and deletes at once: the same as a full build")
    func largeLedger() {
        var generator = SeededGenerator(seed: 341)
        let accountIDs = [F.usdID, F.savingsID, F.walletID]
        var rows = (0..<2_000)
            .map { index in
                F.expense(
                    Decimal(index % 97 + 1),
                    on: F.date(2026, 1 + index % 12, 1 + index % 28, index % 24),
                    account: accountIDs[index % 3],
                    created: F.date(2026, 1, 1, index % 24),
                )
            }
        let before = rows
        var changed: Set<UUID> = []
        for step in 0..<40 {
            let index = Int(generator.next() % UInt64(rows.count))
            switch step % 3 {
            case 0:
                rows[index].date = F.date(2026, 1 + step % 12, 1 + step % 28, 6)
                changed.insert(rows[index].id)
            case 1:
                let added = F.expense(
                    Decimal(step),
                    on: F.date(2026, 11, 1 + step % 28),
                    account: accountIDs[step % 3],
                )
                rows.append(added)
                changed.insert(added.id)
            default:
                changed.insert(rows.remove(at: index).id)
            }
        }
        check(before, rows, changed: changed)
    }
}

/// A fixed pseudo-random sequence (SplitMix64), so the large test is the same on every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
