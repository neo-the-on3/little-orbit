import Foundation
import LittleOrbitDomain
import Testing

/// Duplicate's copy rules and which rows offer Refund and Duplicate (#34, D65, D117.2, D117.3).
@Suite("Transaction duplicate")
struct TransactionDuplicateTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    private let today = F.date(2026, 10, 23, 9, 30)

    @Test("A reconciled expense copies amount, account, category, payee, description, notes and tags (S24)")
    func copiesTheFields() throws {
        let original = Transaction(
            type: .expense,
            amount: 1_000,
            date: F.date(2026, 10, 1),
            timeZoneID: F.india,
            accountID: F.savingsID,
            categoryID: UUID(),
            payeeID: UUID(),
            details: "Birthday cake",
            note: "Paid at the counter",
            scheduledTemplateID: UUID(),
            scheduledOccurrenceDate: F.date(2026, 10, 1),
            status: .reconciled,
            tagIDs: [UUID(), UUID()],
        )
        let copy = try TransactionDuplicate.copy(of: original, splits: [], now: today, timeZoneID: F.india)
        let made = copy.transaction
        #expect(made.id != original.id)
        #expect(made.date == today)
        #expect(made.createdAt == today)
        #expect(made.type == original.type)
        #expect(made.amount == original.amount)
        #expect(made.accountID == original.accountID)
        #expect(made.categoryID == original.categoryID)
        #expect(made.payeeID == original.payeeID)
        #expect(made.details == original.details)
        #expect(made.note == original.note)
        #expect(made.tagIDs == original.tagIDs)
        #expect(made.status == TransactionStatus.newTransactionDefault)
        #expect(made.scheduledTemplateID == nil)
        #expect(made.scheduledOccurrenceDate == nil)
        #expect(made.refundOfID == nil)
        #expect(!made.isRefund)
        #expect(copy.splits.isEmpty)
    }

    @Test("A transfer ₹1,000 → $12.00 keeps both accounts and both amounts (S26)")
    func copiesATransfer() throws {
        let transfer = F.transfer(1_000, on: F.date(2026, 10, 2), to: F.usdID, received: 12)
        let copy = try TransactionDuplicate.copy(of: transfer, splits: [], now: today).transaction
        #expect(copy.accountID == F.savingsID)
        #expect(copy.transferAccountID == F.usdID)
        #expect(copy.amount == 1_000)
        #expect(copy.destinationAmount == 12)
        #expect(copy.status == TransactionStatus.newTransactionDefault)
    }

    @Test("A split copies its lines, amounts, categories and line notes, in order, onto the copy (S25)")
    func copiesSplitLines() throws {
        let original = F.expense(90, on: F.date(2026, 10, 3))
        let lines = [
            TransactionSplit(
                transactionID: original.id,
                categoryID: UUID(),
                amount: 50,
                note: "paper towels",
                sortOrder: 1,
            ),
            TransactionSplit(transactionID: original.id, categoryID: UUID(), amount: 40, note: "café 🍰", sortOrder: 0),
        ]
        let copy = try TransactionDuplicate.copy(of: original, splits: lines, now: today)
        #expect(copy.splits.map(\.amount) == [40, 50])
        #expect(copy.splits.map(\.categoryID) == [lines[1].categoryID, lines[0].categoryID])
        #expect(copy.splits.map(\.note) == ["café 🍰", "paper towels"])
        #expect(copy.splits.allSatisfy { $0.transactionID == copy.transaction.id })
        #expect(Set(copy.splits.map(\.id)).isDisjoint(with: lines.map(\.id)))
    }

    @Test("A refund can't be duplicated (D65, D117.3)")
    func refundIsRejected() {
        let refund = Transaction(
            type: .income,
            amount: 300,
            accountID: F.savingsID,
            refundOfID: UUID(),
            isRefund: true,
        )
        #expect(throws: LedgerValidationError.refundCannotBeDuplicated) {
            try TransactionDuplicate.copy(of: refund, splits: [], now: today)
        }
        var orphan = refund
        orphan.refundOfID = nil
        #expect(throws: LedgerValidationError.refundCannotBeDuplicated) {
            try TransactionDuplicate.copy(of: orphan, splits: [], now: today)
        }
    }

    @Test(
        "Expense rows offer Refund and Duplicate; income and transfers Duplicate only; refunds neither (D117.2, D117.3)"
    )
    func actions() {
        let expense = TransactionActions(for: F.expense(100, on: today))
        #expect(expense.canRefund && expense.duplicate == .available)
        let income = TransactionActions(for: F.income(100, on: today))
        #expect(!income.canRefund && income.duplicate == .available)
        let transfer = TransactionActions(for: F.transfer(100, on: today))
        #expect(!transfer.canRefund && transfer.duplicate == .available)
        let refund = TransactionActions(
            for: Transaction(type: .income, amount: 50, accountID: F.savingsID, refundOfID: UUID(), isRefund: true)
        )
        #expect(!refund.canRefund && refund.duplicate == .disabledForRefund)
    }

    @Test("Cmd+D and Cmd+R act on exactly one selected row (#31, S43)")
    func selection() {
        let one = F.expense(100, on: today)
        #expect(TransactionActions.forSelection([one]) == TransactionActions(for: one))
        #expect(TransactionActions.forSelection([one, F.expense(5, on: today)]) == nil)
        #expect(TransactionActions.forSelection([]) == nil)
    }
}

/// `DuplicateTransactionUseCase` over the fake repository.
@MainActor
@Suite("Duplicate use case")
struct DuplicateUseCaseTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    private let today = F.date(2026, 10, 23, 9, 30)

    @Test("Duplicating saves a copy dated today; Undo deletes only the copy (S29)")
    func duplicateAndUndo() throws {
        let original = F.expense(500, on: F.date(2026, 10, 19))
        let repository = try FakeLedgerRepository(accounts: F.accounts, transactions: [original])
        let useCases = TransactionUseCases(repository: repository)
        let change = try useCases.duplicate.duplicate(id: original.id, now: today)
        guard case .added(let ids) = change, let copyID = ids.first else {
            Issue.record("Expected .added, got \(change)")
            return
        }
        let copy = try #require(try repository.transactions().first { $0.id == copyID })
        #expect(copy.date == today)
        #expect(copy.amount == 500)
        _ = try useCases.changes.revertNow(change)
        #expect(try repository.transactions().map(\.id) == [original.id])
    }

    @Test("Duplicating a split copies its lines, and Undo removes them with the copy")
    func duplicateSplit() throws {
        let original = F.expense(90, on: F.date(2026, 10, 19))
        let repository = try FakeLedgerRepository(accounts: F.accounts, transactions: [original])
        try repository.seedDefaultCategories()
        let expenseCategories = try repository.categories().filter { $0.kind == .expense }.prefix(2).map(\.id)
        try repository.replaceSplits(
            [
                TransactionSplit(categoryID: expenseCategories[0], amount: 40, note: "line note", sortOrder: 0),
                TransactionSplit(categoryID: expenseCategories[1], amount: 50, sortOrder: 1),
            ],
            for: original.id,
        )
        let useCases = TransactionUseCases(repository: repository)
        let change = try useCases.duplicate.duplicate(id: original.id, now: today)
        guard case .added(let ids) = change, let copyID = ids.first else {
            Issue.record("Expected .added, got \(change)")
            return
        }
        let lines = try repository.splits(for: copyID)
        #expect(lines.map(\.amount) == [40, 50])
        #expect(lines.map(\.note) == ["line note", nil])
        _ = try useCases.changes.revertNow(change)
        #expect(try repository.splits(for: copyID).isEmpty)
        #expect(try repository.splits(for: original.id).count == 2)
    }

    @Test("D216, P1: a Berlin expense duplicated at 15:40 in Kolkata is dated then, stored in Kolkata, stamped now")
    func duplicateTakesNowAndTheDeviceZone() throws {
        let berlin = "Europe/Berlin"
        let original = F.expense(250, on: F.date(2026, 10, 3, 8, 10, zone: berlin), zone: berlin)
        let repository = try FakeLedgerRepository(accounts: F.accounts, transactions: [original])
        let stored = try #require(try repository.transactions().first)
        let duplicate = DefaultDuplicateTransactionUseCase(repository: repository, timeZoneID: { F.india })
        let now = F.date(2026, 10, 21, 15, 40)
        let change = try duplicate.duplicate(id: original.id, now: now)
        guard case .added(let ids) = change, let copyID = ids.first else {
            Issue.record("Expected .added, got \(change)")
            return
        }
        let copy = try #require(try repository.transactions().first { $0.id == copyID })
        #expect(copy.date == now)
        #expect(copy.timeZoneID == F.india)
        #expect(TransactionCalendar.calendarDay(of: copy) == F.day(2026, 10, 21))
        #expect(copy.createdAt == now)
        #expect(copy.updatedAt == now)
        #expect(try repository.transactions().first { $0.id == original.id } == stored)
    }

    @Test("D216, P2: the copy sorts by when it was made, between today's 09:00 and 18:00 entries")
    func copySortsByItsTime() throws {
        let morning = F.expense(10, on: F.date(2026, 10, 21, 9, 0))
        let evening = F.expense(20, on: F.date(2026, 10, 21, 18, 0))
        let repository = try FakeLedgerRepository(accounts: F.accounts, transactions: [morning, evening])
        let duplicate = DefaultDuplicateTransactionUseCase(repository: repository, timeZoneID: { F.india })
        _ = try duplicate.duplicate(id: morning.id, now: F.date(2026, 10, 21, 15, 40))
        let day = try #require(TransactionCalendar.groups(try repository.transactions()).first)
        #expect(day.transactions.map(\.amount) == [20, 10, 10])
        #expect(day.transactions[1].id != morning.id)
    }

    @Test("A missing transaction or a refund writes nothing and throws")
    func failures() throws {
        let original = F.expense(500, on: F.date(2026, 10, 19))
        let repository = try FakeLedgerRepository(accounts: F.accounts, transactions: [original])
        let duplicate = TransactionUseCases(repository: repository).duplicate
        #expect(throws: LedgerValidationError.missingTransaction) {
            try duplicate.duplicate(id: UUID(), now: today)
        }
        #expect(try repository.transactions().count == 1)
    }
}
