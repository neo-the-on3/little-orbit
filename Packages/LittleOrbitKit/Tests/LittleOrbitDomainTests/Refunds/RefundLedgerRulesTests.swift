import Foundation
import LittleOrbitDomain
import Testing

/// The refund rules in `LedgerBook`, which every store applies on save and delete (#55; D19, D33, D35).
/// Test names carry the acceptance criterion (AC) or Tester's QA id from #55.
@Suite("Refund ledger rules (#55)")
struct RefundLedgerRulesTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name
    typealias R = RefundFixture  // swiftlint:disable:this type_name

    private let now = F.date(2026, 10, 23)

    private func save(_ transaction: Transaction, in snapshot: LedgerSnapshot) throws -> LedgerSnapshot {
        try LedgerBook.savingTransaction(transaction, in: snapshot, now: now)
    }

    private func delete(_ id: UUID, in snapshot: LedgerSnapshot) throws -> LedgerSnapshot {
        try LedgerBook.deletingTransaction(id: id, in: snapshot, now: now)
    }

    // MARK: - Creating a refund (AC 1)

    @Test("AC1, v1 Happy 1: a refund is an income with isRefund, the link and the expense's category")
    func refundOfExpense() throws {
        let expense = R.expense(50)
        let refund = R.refund(20, of: expense)
        let snapshot = try R.saving([expense, refund])
        let stored = try #require(snapshot.transaction(refund.id))
        #expect(stored.type == .income)
        #expect(stored.isRefund)
        #expect(stored.refundOfID == expense.id)
        #expect(stored.categoryID == R.groceriesID)
        #expect(RefundStatus(of: stored) == .linked(originalID: expense.id))
    }

    @Test("AC1, v1 Validation 1–2: an expense category on income is allowed only for a refund")
    func expenseCategoryOnlyForRefunds() throws {
        var income = F.income(2_000, on: R.october)
        income.categoryID = R.groceriesID
        #expect(throws: LedgerValidationError.categoryKindMismatch) { try save(income, in: R.ledger) }
        income.categoryID = R.salaryID
        #expect(RefundStatus(of: try #require(try save(income, in: R.ledger).transaction(income.id))) == .notRefund)
        let expense = R.expense(5_000)
        _ = try R.saving([expense, R.refund(2_000, of: expense)])
    }

    @Test("A1 (D33.1): a link with isRefund false is rejected, never switched to a refund, and nothing is written")
    func linkWithoutFlag() throws {
        let expense = R.expense(5_000)
        let snapshot = try R.saving([expense])
        let mismatched = R.refund(2_000, of: expense, isRefund: false)
        #expect(throws: LedgerValidationError.refundLinkWithoutRefundFlag) { try save(mismatched, in: snapshot) }
        #expect(snapshot.transaction(mismatched.id) == nil)
    }

    @Test("Only an income can be a refund: isRefund on an expense or a transfer is rejected")
    func refundMustBeIncome() throws {
        var expense = R.expense(500)
        expense.isRefund = true
        #expect(throws: LedgerValidationError.refundMustBeIncome) { try save(expense, in: R.ledger) }
        var transfer = F.transfer(500, on: R.october)
        transfer.isRefund = true
        #expect(throws: LedgerValidationError.refundMustBeIncome) { try save(transfer, in: R.ledger) }
    }

    @Test("v1 Validation 4: a refund can only point to an expense, never an income, a transfer or a refund")
    func originalMustBeExpense() throws {
        let expense = R.expense(5_000)
        var salary = F.income(9_000, on: R.october)
        salary.categoryID = R.salaryID
        let transfer = F.transfer(1_000, on: R.october)
        let refund = R.refund(1_000, of: expense)
        let snapshot = try R.saving([expense, salary, transfer, refund])
        for original in [salary, transfer, refund] {
            var bad = R.refund(100, of: original, in: R.groceriesID)
            bad.refundOfID = original.id
            #expect(throws: LedgerValidationError.refundOriginalNotExpense) { try save(bad, in: snapshot) }
        }
    }

    @Test("v1 Validation 5: a link to an id that doesn't exist, or to the refund itself, is rejected")
    func originalMustExist() throws {
        var refund = R.refund(100, of: nil)
        refund.refundOfID = UUID()
        #expect(throws: LedgerValidationError.refundOriginalMissing) { try save(refund, in: R.ledger) }
        refund.refundOfID = refund.id
        #expect(throws: LedgerValidationError.refundOriginalMissing) { try save(refund, in: R.ledger) }
    }

    @Test("A3, F4(c), F7, G3: a refund with an income category is rejected, linked or not, and never replaced")
    func incomeCategoryRejected() throws {
        let expense = R.expense(5_000)
        let snapshot = try R.saving([expense])
        let linked = R.refund(2_000, of: expense, in: R.salaryID)
        #expect(throws: LedgerValidationError.categoryKindMismatch) { try save(linked, in: snapshot) }
        #expect(snapshot.transaction(linked.id) == nil)
        let orphan = R.refund(2_000, of: nil, in: R.salaryID)
        #expect(throws: LedgerValidationError.categoryKindMismatch) { try save(orphan, in: snapshot) }
    }

    @Test("v1 Validation 7: a refund of 0 or less is rejected like any transaction")
    func refundAmountMustBePositive() throws {
        let expense = R.expense(5_000)
        let snapshot = try R.saving([expense])
        for amount: Decimal in [0, -20] {
            #expect(throws: LedgerValidationError.invalidAmount) {
                try save(R.refund(amount, of: expense), in: snapshot)
            }
        }
    }

    @Test("A2b, F4(a), F5 (D35.2): an unlinked refund with an expense category is valid in the ledger")
    func unlinkedRefundAccepted() throws {
        let orphan = R.refund(1_200, of: nil)
        let stored = try #require(try save(orphan, in: R.ledger).transaction(orphan.id))
        #expect(stored.isRefund)
        #expect(stored.categoryID == R.groceriesID)
        #expect(RefundStatus(of: stored) == .originalDeleted)
    }

    // MARK: - Cap (D33.2, D35.1)

    @Test("B1, B2: a refund of the full amount saves; one paisa more is rejected")
    func capAtFullAmount() throws {
        let expense = R.expense(Decimal(string: "5000.00")!)
        let snapshot = try R.saving([expense])
        _ = try save(R.refund(Decimal(string: "5000.00")!, of: expense), in: snapshot)
        #expect(throws: LedgerValidationError.refundsExceedOriginal(5_000)) {
            try save(R.refund(Decimal(string: "5000.01")!, of: expense), in: snapshot)
        }
    }

    @Test("B3: the cap counts every linked refund")
    func capCountsEveryRefund() throws {
        let expense = R.expense(5_000)
        let snapshot = try R.saving([expense, R.refund(2_000, of: expense), R.refund(2_500, of: expense)])
        #expect(throws: LedgerValidationError.refundsExceedOriginal(500)) {
            try save(R.refund(Decimal(string: "500.01")!, of: expense), in: snapshot)
        }
        _ = try save(R.refund(500, of: expense), in: snapshot)
    }

    @Test("B4: editing a refund counts its new amount, not old plus new")
    func capCountsEditedAmount() throws {
        let expense = R.expense(5_000)
        var second = R.refund(2_500, of: expense)
        let snapshot = try R.saving([expense, R.refund(2_000, of: expense), second])
        second.amount = Decimal(string: "3000.01")!
        #expect(throws: LedgerValidationError.refundsExceedOriginal(3_000)) { try save(second, in: snapshot) }
        second.amount = 3_000
        #expect(try save(second, in: snapshot).transaction(second.id)?.amount == 3_000)
    }

    @Test("B5, Amounts 1: exact Decimal sums, with no rounding left over")
    func capIsExact() throws {
        let expense = R.expense(Decimal(string: "1999.99")!)
        let snapshot = try R.saving([
            expense, R.refund(Decimal(string: "999.99")!, of: expense), R.refund(1_000, of: expense),
        ])
        #expect(throws: LedgerValidationError.refundsExceedOriginal(0)) {
            try save(R.refund(Decimal(string: "0.01")!, of: expense), in: snapshot)
        }
    }

    @Test("D258, P45: an edited refund over the cap is refused with the limit, leaving the edited refund out")
    func capCarriesLimit() throws {
        let expense = R.expense(1_000)
        var edited = R.refund(300, of: expense)
        let snapshot = try R.saving([expense, edited])
        edited.amount = 1_001
        #expect(throws: LedgerValidationError.refundsExceedOriginal(1_000)) { try save(edited, in: snapshot) }
        edited.amount = 300
        let withAnother = try R.saving([expense, edited, R.refund(200, of: expense)])
        edited.amount = 801
        #expect(throws: LedgerValidationError.refundsExceedOriginal(800)) { try save(edited, in: withAnother) }
        edited.amount = 800
        #expect(try save(edited, in: withAnother).transaction(edited.id)?.amount == 800)
    }

    @Test("B6 (D35.1): an expense can't go below its refunds; the error carries their total")
    func expenseFloor() throws {
        var expense = R.expense(5_000)
        let snapshot = try R.saving([expense, R.refund(2_000, of: expense), R.refund(2_500, of: expense)])
        expense.amount = Decimal(string: "4499.99")!
        #expect(throws: LedgerValidationError.amountBelowRefunds(4_500)) { try save(expense, in: snapshot) }
        #expect(snapshot.transaction(expense.id)?.amount == 5_000)
        expense.amount = 4_500
        #expect(try save(expense, in: snapshot).transaction(expense.id)?.amount == 4_500)
    }

    @Test("B8, F8: an unlinked refund counts toward no expense's floor or cap")
    func orphanOutsideCap() throws {
        var unrelated = R.expense(1_000)
        let snapshot = try R.saving([R.refund(2_000, of: nil), unrelated])
        unrelated.amount = 500
        _ = try save(unrelated, in: snapshot)
        // F8: an orphan of ₹3,000 stays unlinked when a ₹2,000 expense comes in later.
        let orphan = R.refund(3_000, of: nil)
        let later = try R.saving([orphan, R.expense(2_000)])
        #expect(later.transaction(orphan.id)?.refundOfID == nil)
    }

    // MARK: - Category follows the expense (D33.4)

    @Test("D1: changing the expense's category moves its refunds in the same save")
    func refundsFollowCategory() throws {
        var expense = R.expense(5_000)
        let first = R.refund(2_000, of: expense)
        let second = R.refund(500, of: expense)
        let snapshot = try R.saving([expense, first, second])
        expense.categoryID = R.diningID
        let saved = try save(expense, in: snapshot)
        #expect(saved.transaction(first.id)?.categoryID == R.diningID)
        #expect(saved.transaction(second.id)?.categoryID == R.diningID)
        #expect(saved.transaction(first.id)?.updatedAt == now)
    }

    @Test("D3: a linked refund's own category can't be changed")
    func linkedCategoryLocked() throws {
        let expense = R.expense(5_000)
        var refund = R.refund(2_000, of: expense)
        let snapshot = try R.saving([expense, refund])
        refund.categoryID = R.shoppingID
        #expect(throws: LedgerValidationError.refundCategoryMismatch) { try save(refund, in: snapshot) }
        refund.categoryID = nil
        #expect(throws: LedgerValidationError.refundCategoryMismatch) { try save(refund, in: snapshot) }
    }

    @Test("D5: clearing the expense's category leaves its refunds uncategorised too")
    func refundsFollowUncategorised() throws {
        var expense = R.expense(5_000)
        let refund = R.refund(2_000, of: expense)
        let snapshot = try R.saving([expense, refund])
        expense.categoryID = nil
        let saved = try save(expense, in: snapshot)
        let stored = try #require(saved.transaction(refund.id))
        #expect(stored.categoryID == nil)
        #expect(stored.isRefund)
    }

    // MARK: - Currency and account (D33.5)

    @Test("E1, E2: a refund may land on another account in the same currency; each balance moves by its own")
    func sameCurrencyAnyAccount() throws {
        let expense = R.expense(5_000, account: R.cardID)
        let toCard = R.refund(2_000, of: expense, account: R.cardID)
        let card = try R.saving([expense, toCard])
        #expect(try LedgerBook.balance(of: R.cardID, in: card) == -3_000)
        let toSavings = R.refund(2_000, of: expense, account: F.savingsID)
        let split = try R.saving([expense, toSavings])
        #expect(try LedgerBook.balance(of: R.cardID, in: split) == -5_000)
        #expect(try LedgerBook.balance(of: F.savingsID, in: split) == 12_000)
    }

    @Test("E3, E4: a refund to an account in another currency is rejected, new or moved")
    func refundCurrencyMustMatch() throws {
        let expense = R.expense(5_000)
        var refund = R.refund(2_000, of: expense)
        let snapshot = try R.saving([expense, refund])
        let usd = R.refund(24, of: expense, account: F.usdID)
        #expect(throws: LedgerValidationError.refundCurrencyMismatch) { try save(usd, in: snapshot) }
        refund.accountID = F.usdID
        refund.amount = 24
        #expect(throws: LedgerValidationError.refundCurrencyMismatch) { try save(refund, in: snapshot) }
    }

    @Test("E5: an expense with linked refunds can't move to an account in another currency")
    func expenseCurrencyLockedByRefunds() throws {
        var expense = R.expense(5_000)
        let refund = R.refund(2_000, of: expense)
        let snapshot = try R.saving([expense, refund])
        expense.accountID = F.usdID
        expense.amount = 60
        #expect(throws: LedgerValidationError.refundCurrencyMismatch) { try save(expense, in: snapshot) }
        #expect(snapshot.transaction(refund.id)?.refundOfID == expense.id)
        expense.accountID = F.walletID
        expense.amount = 5_000
        _ = try save(expense, in: snapshot)
    }

    // MARK: - Deleting the original (AC 3, D19)

    @Test("AC3, A4, v1 Happy 4: deleting the expense unlinks its refund, which keeps isRefund and its category")
    func deleteUnlinks() throws {
        let expense = R.expense(5_000)
        var refund = R.refund(2_000, of: expense)
        let snapshot = try delete(expense.id, in: R.saving([expense, refund]))
        let stored = try #require(snapshot.transaction(refund.id))
        #expect(stored.refundOfID == nil)
        #expect(stored.isRefund)
        #expect(stored.categoryID == R.groceriesID)
        #expect(stored.updatedAt == now)
        #expect(RefundStatus(of: stored) == .originalDeleted)
        // A4: the orphan still passes when edited.
        refund = stored
        refund.note = "returned at the counter"
        #expect(try save(refund, in: snapshot).transaction(refund.id)?.note == "returned at the counter")
    }

    @Test("v1 Edge 6: deleting only the refund leaves the expense unchanged")
    func deleteRefundOnly() throws {
        let expense = R.expense(5_000)
        let refund = R.refund(2_000, of: expense)
        let before = try R.saving([expense, refund])
        let after = try delete(refund.id, in: before)
        #expect(after.transaction(expense.id) == before.transaction(expense.id))
    }

    @Test("Deleting an account unlinks refunds elsewhere of its expenses (D19)")
    func deleteAccountUnlinks() throws {
        let expense = R.expense(5_000, account: R.cardID)
        let refund = R.refund(2_000, of: expense, account: F.savingsID)
        let snapshot = try LedgerBook.deletingAccount(id: R.cardID, in: R.saving([expense, refund]), now: now)
        let stored = try #require(snapshot.transaction(refund.id))
        #expect(stored.refundOfID == nil)
        #expect(stored.isRefund)
        #expect(stored.categoryID == R.groceriesID)
    }

    @Test("An expense saved as deleted (a sync tombstone) unlinks its refunds too")
    func tombstoneUnlinks() throws {
        var expense = R.expense(5_000)
        let refund = R.refund(2_000, of: expense)
        let snapshot = try R.saving([expense, refund])
        expense.deletedAt = now
        #expect(try save(expense, in: snapshot).transaction(refund.id)?.refundOfID == nil)
    }

    // MARK: - Orphans (D35.5)

    @Test("G1, G2: an orphan's category can change to another expense category or Uncategorised")
    func orphanCategoryEditable() throws {
        var orphan = R.refund(2_000, of: nil)
        let snapshot = try R.saving([orphan])
        orphan.categoryID = R.shoppingID
        #expect(try save(orphan, in: snapshot).transaction(orphan.id)?.categoryID == R.shoppingID)
        orphan.categoryID = nil
        let cleared = try #require(try save(orphan, in: snapshot).transaction(orphan.id))
        #expect(cleared.categoryID == nil)
        #expect(cleared.isRefund)
    }

    // MARK: - What a refund's original must stay

    @Test("An expense with linked refunds can't become an income")
    func originalStaysExpense() throws {
        var expense = R.expense(5_000)
        let snapshot = try R.saving([expense, R.refund(2_000, of: expense)])
        expense.type = .income
        expense.categoryID = R.salaryID
        #expect(throws: LedgerValidationError.originalHasRefunds) { try save(expense, in: snapshot) }
    }

    @Test("Schema V1 has no line link: no refund of a split expense, and no split of an expense with refunds")
    func noSplitRefundsInV1() throws {
        let split = R.expense(6_000, in: nil)
        let lines = [
            TransactionSplit(categoryID: R.groceriesID, amount: 4_000),
            TransactionSplit(categoryID: R.shoppingID, amount: 2_000, sortOrder: 1),
        ]
        let snapshot = try LedgerBook.replacingSplits(lines, for: split.id, in: R.saving([split]), now: now)
        #expect(throws: LedgerValidationError.refundOriginalIsSplit) {
            try save(R.refund(1_500, of: split, in: R.shoppingID), in: snapshot)
        }
        let expense = R.expense(6_000)
        let refunded = try R.saving([expense, R.refund(1_500, of: expense)])
        #expect(throws: LedgerValidationError.originalHasRefunds) {
            try LedgerBook.replacingSplits(lines, for: expense.id, in: refunded, now: now)
        }
    }

    // MARK: - Export (AC 5)

    @Test("AC5, F5: a backup round trip keeps a linked and an unlinked refund's isRefund, link and category")
    func backupKeepsRefunds() throws {
        let expense = R.expense(5_000)
        let linked = R.refund(2_000, of: expense)
        let orphan = R.refund(800, of: nil, in: R.shoppingID)
        let ledger = try R.saving([expense, linked, orphan])
        let manifest = BackupManifest(
            kind: .manual,
            createdAt: now,
            nameIndex: 1,
            schemaVersion: "1.0.0",
            accountCount: ledger.accounts.count,
            transactionCount: 3,
            attachmentCount: 0,
        )
        let codec = BackupCodec(hashing: FakeBackupHashing())
        let restored = try codec.decode(codec.encode(BackupContents(manifest: manifest, ledger: ledger))).ledger
        let back = try #require(restored.transaction(orphan.id))
        #expect(back.isRefund)
        #expect(back.refundOfID == nil)
        #expect(back.categoryID == R.shoppingID)
        #expect(restored.transaction(linked.id)?.refundOfID == expense.id)
    }
}
