import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// #235: each kind of kept value that links to a record the write deletes goes to the whole-store path, so an
/// incremental delete never cascades into a record the ledger keeps. In each case only that one kept value links
/// to the deleted record, it isn't rewritten, and no transaction uses the record. Plain values, every platform.
@Suite("Kept links to a deleted record (#235)")
struct LedgerLinkTests {
    static func reason(_ base: LedgerSnapshot, _ target: LedgerSnapshot) -> LedgerWriteSet.WholeStoreReason? {
        #expect(LedgerWriteSet(from: base, to: base).wholeStoreReason == nil)
        return LedgerWriteSet(from: base, to: target).wholeStoreReason
    }

    /// The base ledger with one more category, used by nothing yet.
    static func withSpare() -> (LedgerSnapshot, TransactionCategory) {
        var base = LedgerWriteSetTests.ledger()
        let spare = TransactionCategory(name: "Spare", createdAt: LedgerWriteSetTests.created)
        base.categories.append(spare)
        return (base, spare)
    }

    /// The base ledger with one more transaction, used by nothing yet.
    static func withSecondTransaction() -> (LedgerSnapshot, Transaction) {
        var base = LedgerWriteSetTests.ledger()
        let second = Transaction(
            amount: 90,
            date: LedgerWriteSetTests.created,
            timeZoneID: "Asia/Kolkata",
            accountID: base.accounts[0].id,
            createdAt: LedgerWriteSetTests.created,
        )
        base.transactions.append(second)
        return (base, second)
    }

    @Test("A kept subcategory whose parent is deleted")
    func categoryParent() {
        var (base, spare) = Self.withSpare()
        base.categories.append(
            TransactionCategory(name: "Child", parentID: spare.id, createdAt: LedgerWriteSetTests.created)
        )
        var target = base
        target.categories.removeAll { $0.id == spare.id }
        #expect(Self.reason(base, target) == .danglingReference)
    }

    @Test("A kept payee whose default category is deleted")
    func payeeDefaultCategory() {
        var (base, spare) = Self.withSpare()
        base.payees[0].defaultCategoryID = spare.id
        var target = base
        target.categories.removeAll { $0.id == spare.id }
        #expect(Self.reason(base, target) == .danglingReference)
    }

    @Test("A kept split whose category is deleted")
    func splitCategory() {
        var (base, spare) = Self.withSpare()
        base.splits[0].categoryID = spare.id
        var target = base
        target.categories.removeAll { $0.id == spare.id }
        #expect(Self.reason(base, target) == .danglingReference)
    }

    @Test("A kept split whose transaction is deleted")
    func splitTransaction() {
        var (base, second) = Self.withSecondTransaction()
        base.splits.append(TransactionSplit(transactionID: second.id, categoryID: nil, amount: 90))
        var target = base
        target.transactions.removeAll { $0.id == second.id }
        #expect(Self.reason(base, target) == .danglingReference)
    }

    @Test("A kept attachment whose transaction is deleted")
    func attachmentTransaction() {
        var (base, second) = Self.withSecondTransaction()
        base.attachments.append(
            Attachment(
                transactionID: second.id,
                fileName: "ticket.pdf",
                contentType: "application/pdf",
                byteSize: 3,
                createdAt: LedgerWriteSetTests.created,
            )
        )
        var target = base
        target.transactions.removeAll { $0.id == second.id }
        #expect(Self.reason(base, target) == .danglingReference)
    }

    @Test("A kept budget one of whose categories is deleted")
    func budgetCategory() {
        var (base, spare) = Self.withSpare()
        base.budgets[0].categoryIDs.append(spare.id)
        var target = base
        target.categories.removeAll { $0.id == spare.id }
        #expect(Self.reason(base, target) == .danglingReference)
    }
}
