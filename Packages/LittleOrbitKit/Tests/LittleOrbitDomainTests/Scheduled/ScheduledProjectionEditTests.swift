import Foundation
import LittleOrbitDomain
import Testing

/// D426.2 (#312 item 1): an account's Upcoming rows read each occurrence's own due day, amount and account, so an
/// occurrence edited with "This occurrence only" shows where and as it will post. Made-up data: Rent ₹25,000
/// monthly on the 1st from 1 Aug 2026, from Everyday Savings; Long Term Fund stands in for the other INR account,
/// and Joint Account for a third.
@MainActor
@Suite("Upcoming rows follow occurrence edits (D426.2)")
struct ScheduledProjectionEditTests {
    private typealias Fix = ScheduledFixture
    private let today = ScheduledFixture.day(2026, 10, 20)
    private static let jointID = UUID(uuidString: "5C000000-0000-4000-8000-0000000000AA")!

    private func scene(
        automatic: Bool = false,
        item: ScheduledItem? = nil,
    ) throws -> (FakeScheduleRepository, ScheduledItem) {
        let rent = item ?? Fix.rent(automatic: automatic)
        var ledger = Fix.ledger
        ledger.accounts.append(
            Account(
                id: Self.jointID,
                name: "Joint Account",
                type: .savings,
                currencyCode: "INR",
                createdAt: Fix.created,
            )
        )
        let repository = FakeScheduleRepository(ledger)
        repository.now = Fix.created
        try repository.useCases().save(rent)
        repository.now = Fix.date(2026, 10, 20)
        return (repository, rent)
    }

    /// Saves "This occurrence only" on the occurrence `key`, as the form opened on it does.
    private func editOne(
        _ id: UUID,
        in repository: FakeScheduleRepository,
        occurrence key: CalendarDay,
        dueDay: CalendarDay? = nil,
        scope: ScheduledEditScope = .thisOccurrence,
        _ change: (inout ScheduledItem) -> Void = { _ in },
    ) throws {
        let current = try #require(repository.snapshot.scheduledItems.first { $0.id == id })
        var item = current.resolved(for: key)
        item.occurrences = current.occurrences
        change(&item)
        let save = ScheduledOccurrenceSave(
            occurrence: key,
            dueDay: dueDay ?? current.dueDay(of: key),
            scope: scope,
        )
        _ = try repository.useCases().update(item, editing: save, payee: nil)
    }

    private func upcoming(_ accountID: UUID, _ repository: FakeScheduleRepository) -> [Transaction] {
        ScheduledProjection.upcoming(on: accountID, in: repository.snapshot, today: today)
    }

    private func rows(_ transactions: [Transaction]) -> [String] {
        transactions.map { transaction in
            let day = TransactionTiming.day(of: transaction)
            return "\(day.day)/\(day.month) \(transaction.amount)"
        }
    }

    @Test("Check 4: 1 Nov moved to 3 Nov, ₹26,000, the other account: it shows there only; 1 Dec stays ₹25,000")
    func movedToAnotherAccount() throws {
        let (repository, rent) = try scene()
        try editOne(rent.id, in: repository, occurrence: Fix.day(2026, 11, 1), dueDay: Fix.day(2026, 11, 3)) {
            $0.amount = 26_000
            $0.accountID = Fix.fundID
        }
        let fund = upcoming(Fix.fundID, repository)
        #expect(rows(fund) == ["3/11 26000"])
        #expect(fund.first?.accountID == Fix.fundID)
        #expect(fund.first?.id == ScheduledKey.transactionID(item: rent.id, day: Fix.day(2026, 11, 1)))
        // Everyday Savings has no 1 Nov row, and still shows its next occurrence, 1 Dec, at the item's amount.
        let savings = upcoming(Fix.savingsID, repository)
        #expect(rows(savings) == ["1/12 25000"])
        #expect(savings.first?.accountID == Fix.savingsID)
    }

    @Test("The account's next occurrence passes over ones moved to another account")
    func nextPassesOverMovedAway() throws {
        let (repository, rent) = try scene()
        for key in [Fix.day(2026, 11, 1), Fix.day(2026, 12, 1)] {
            try editOne(rent.id, in: repository, occurrence: key) { $0.accountID = Fix.fundID }
        }
        let savings = upcoming(Fix.savingsID, repository)
        #expect(rows(savings) == ["1/1 25000"])
        #expect(savings.first?.accountID == Fix.savingsID)
        #expect(rows(upcoming(Fix.fundID, repository)) == ["1/11 25000"])
    }

    @Test("A date-only move shows the occurrence on its new day, and only there")
    func movedDay() throws {
        let (repository, rent) = try scene()
        try editOne(rent.id, in: repository, occurrence: Fix.day(2026, 11, 1), dueDay: Fix.day(2026, 11, 10))
        #expect(rows(upcoming(Fix.savingsID, repository)) == ["10/11 25000"])
    }

    @Test("An occurrence moved into the month ahead shows; one moved past it leaves, and the next one shows instead")
    func movedAcrossHorizon() throws {
        let (repository, rent) = try scene()
        try editOne(rent.id, in: repository, occurrence: Fix.day(2026, 12, 1), dueDay: Fix.day(2026, 11, 15))
        #expect(rows(upcoming(Fix.savingsID, repository)) == ["1/11 25000", "15/11 25000"])
        let (later, other) = try scene()
        try editOne(other.id, in: later, occurrence: Fix.day(2026, 11, 1), dueDay: Fix.day(2026, 11, 28))
        #expect(rows(upcoming(Fix.savingsID, later)) == ["28/11 25000"])
    }

    @Test("Only the edited field is its own: an amount-only edit keeps the day and the account")
    func amountOnly() throws {
        let (repository, rent) = try scene()
        try editOne(rent.id, in: repository, occurrence: Fix.day(2026, 11, 1)) { $0.amount = 26_000 }
        let savings = upcoming(Fix.savingsID, repository)
        #expect(rows(savings) == ["1/11 26000"])
        #expect(upcoming(Fix.fundID, repository).isEmpty)
    }

    @Test("The Upcoming row is the transaction catch-up records: same ID, day, amount and account; balances exact")
    func matchesPosting() throws {
        let (repository, rent) = try scene(automatic: true)
        _ = try repository.useCases().catchUp(atLaunch: true)
        try editOne(rent.id, in: repository, occurrence: Fix.day(2026, 11, 1), dueDay: Fix.day(2026, 11, 3)) {
            $0.amount = 26_000
            $0.accountID = Fix.fundID
        }
        let projected = try #require(upcoming(Fix.fundID, repository).first)
        let savingsBefore = try LedgerBook.balance(of: Fix.savingsID, in: repository.snapshot)
        let fundBefore = try LedgerBook.balance(of: Fix.fundID, in: repository.snapshot)
        repository.now = Fix.date(2026, 11, 4)
        _ = try repository.useCases().catchUp(atLaunch: true)
        let posted = try #require(repository.snapshot.transactions.first { $0.id == projected.id })
        #expect(TransactionTiming.day(of: posted) == TransactionTiming.day(of: projected))
        #expect(posted.amount == projected.amount)
        #expect(posted.accountID == projected.accountID)
        #expect(try LedgerBook.balance(of: Fix.fundID, in: repository.snapshot) == fundBefore - 26_000)
        #expect(try LedgerBook.balance(of: Fix.savingsID, in: repository.snapshot) == savingsBefore)
    }

    @Test("N1: an overdue occurrence moved into the month ahead shows on its new day, by its own key")
    func overdueMovedIntoHorizon() throws {
        let (repository, rent) = try scene()
        try editOne(rent.id, in: repository, occurrence: Fix.day(2026, 10, 1), dueDay: Fix.day(2026, 10, 25))
        let savings = upcoming(Fix.savingsID, repository)
        #expect(rows(savings) == ["25/10 25000", "1/11 25000"])
        #expect(savings.first?.id == ScheduledKey.transactionID(item: rent.id, day: Fix.day(2026, 10, 1)))
    }

    @Test("N1: the account's next occurrence is the one of that day's that's still its own, not the first")
    func nextAmongSameDay() throws {
        let (repository, rent) = try scene()
        // 1 Nov and 1 Dec go to Long Term Fund; 1 Jan moves onto 1 Dec, the day another occurrence moved away from.
        for key in [Fix.day(2026, 11, 1), Fix.day(2026, 12, 1)] {
            try editOne(rent.id, in: repository, occurrence: key) { $0.accountID = Fix.fundID }
        }
        try editOne(rent.id, in: repository, occurrence: Fix.day(2027, 1, 1), dueDay: Fix.day(2026, 12, 1))
        let savings = upcoming(Fix.savingsID, repository)
        #expect(rows(savings) == ["1/12 25000"])
        #expect(savings.map(\.id) == [ScheduledKey.transactionID(item: rent.id, day: Fix.day(2027, 1, 1))])
    }

    @Test("N1: a transfer occurrence whose To account moved shows on the new To account; the old one shows the next")
    func transferToMoved() throws {
        let (repository, transfer) = try scene(item: Fix.transfer(start: Fix.day(2026, 8, 1), end: nil))
        try editOne(transfer.id, in: repository, occurrence: Fix.day(2026, 11, 1)) {
            $0.transferAccountID = Self.jointID
        }
        let joint = upcoming(Self.jointID, repository)
        #expect(rows(joint) == ["1/11 10000"])
        #expect(joint.first?.transferAccountID == Self.jointID)
        #expect(rows(upcoming(Fix.fundID, repository)) == ["1/12 10000"])
    }

    @Test("D433.1: an All future move kept as pending in a paid month shows once, on its day, by its own key")
    func allFutureMoveKeptPending() throws {
        let (repository, rent) = try scene()
        for month in 8...10 {
            let day = Fix.day(2026, month, 1)
            _ = try repository.useCases().pay(itemID: rent.id, occurrence: day, on: day, custom: nil)
        }
        let moved = Fix.day(2026, 10, 31)
        try editOne(rent.id, in: repository, occurrence: Fix.day(2026, 11, 1), dueDay: moved, scope: .allFuture)
        #expect(repository.snapshot.scheduledItems.first?.occurrence(on: moved)?.outcome == .pending)
        let savings = upcoming(Fix.savingsID, repository)
        #expect(rows(savings) == ["31/10 25000"])
        #expect(savings.map(\.id) == [ScheduledKey.transactionID(item: rent.id, day: moved)])
    }
}
