import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitPersistence

/// #235: what an incremental write changes, worked out from the ledger as stored and the ledger to store. Made-up
/// records; plain values, so these run on every platform.
@Suite("Incremental write set (#235)")
struct LedgerWriteSetTests {
    static let created = Date(timeIntervalSince1970: 1_790_000_000)
    static let day = CalendarDay(year: 2026, month: 11, day: 1)

    /// One account, a category with a subcategory, a payee, a tag, a transaction with a split and an
    /// attachment, a budget with a limit, and a scheduled item with an occurrence.
    static func ledger() -> LedgerSnapshot {
        let account = Account(name: "Everyday Savings", currencyCode: "INR", createdAt: created)
        let food = TransactionCategory(name: "Food", createdAt: created)
        let snacks = TransactionCategory(name: "Snacks", parentID: food.id, createdAt: created)
        let payee = Payee(name: "Corner Shop", defaultCategoryID: food.id, createdAt: created)
        let tag = Tag(name: "Weekend", createdAt: created)
        let transaction = Transaction(
            amount: 450,
            date: created,
            timeZoneID: "Asia/Kolkata",
            accountID: account.id,
            categoryID: snacks.id,
            payeeID: payee.id,
            tagIDs: [tag.id],
            createdAt: created,
        )
        let split = TransactionSplit(transactionID: transaction.id, categoryID: food.id, amount: 450)
        let attachment = Attachment(
            transactionID: transaction.id,
            fileName: "receipt.jpg",
            contentType: "image/jpeg",
            byteSize: 3,
            createdAt: created,
        )
        let budget = Budget(
            name: "Food",
            currencyCode: "INR",
            categoryIDs: [food.id],
            startDay: day,
            limits: [BudgetLimit(startDay: day, amount: 5000, createdAt: created)],
            createdAt: created,
        )
        let itemID = UUID()
        let item = ScheduledItem(
            id: itemID,
            amount: 1200,
            accountID: account.id,
            payeeID: payee.id,
            startDay: day,
            timeZoneID: "Asia/Kolkata",
            occurrences: [ScheduledOccurrence(id: UUID(), day: day, outcome: .skipped, createdAt: created)],
            createdAt: created,
        )
        return LedgerSnapshot(
            accounts: [account],
            transactions: [transaction],
            categories: [food, snacks],
            payees: [payee],
            tags: [tag],
            splits: [split],
            attachments: [attachment],
            budgets: [budget],
            scheduledItems: [item],
        )
    }

    @Test("The same ledger writes nothing")
    func sameLedger() {
        let ledger = Self.ledger()
        #expect(LedgerWriteSet(from: ledger, to: ledger).isEmpty)
    }

    @Test("An edit writes that record only, a new one is inserted, and a removed one is deleted")
    func editInsertDelete() {
        let base = Self.ledger()
        var target = base
        target.transactions[0].note = "Milk"
        let added = Transaction(amount: 90, timeZoneID: "Asia/Kolkata", accountID: base.accounts[0].id)
        target.transactions.append(added)
        target.tags = []
        target.transactions[0].tagIDs = []
        let changes = LedgerWriteSet(from: base, to: target)
        #expect(changes.transactions.upsertedIDs == [base.transactions[0].id, added.id])
        #expect(changes.tags.deleted == [base.tags[0].id])
        #expect(changes.accounts.isEmpty)
        #expect(changes.payees.isEmpty)
        #expect(changes.attachments.isEmpty)
        #expect(changes.scheduledItems.isEmpty)
        // The split's transaction is written again in the same currency, so the split stays as stored (#265).
        #expect(changes.splits.isEmpty)
        #expect(changes.wholeStoreReason == nil)
    }

    /// #265, the Bulk Edit dirty check: a split is stored in its transaction's account's currency, so it's
    /// written again only when that currency changes, not whenever its transaction is written.
    @Test(
        "A transaction moved to an account in the same currency leaves its splits alone; another currency writes them"
    )
    func movedTransactionSplits() {
        let base = Self.ledger()
        var withCard = base
        withCard.accounts.append(Account(name: "Rewards Card", currencyCode: "INR", createdAt: Self.created))
        var sameCurrency = withCard
        sameCurrency.transactions[0].accountID = withCard.accounts[1].id
        sameCurrency.transactions[0].amount += 1
        let same = LedgerWriteSet(from: withCard, to: sameCurrency)
        #expect(same.transactions.upsertedIDs == [base.transactions[0].id])
        #expect(same.splits.isEmpty)

        var withDollars = base
        withDollars.accounts.append(Account(name: "Travel Card", currencyCode: "USD", createdAt: Self.created))
        var otherCurrency = withDollars
        otherCurrency.transactions[0].accountID = withDollars.accounts[1].id
        let other = LedgerWriteSet(from: withDollars, to: otherCurrency)
        #expect(other.splits.upsertedIDs == [base.splits[0].id])

        var noAccount = base
        noAccount.transactions[0].accountID = nil
        #expect(LedgerWriteSet(from: base, to: noAccount).splits.upsertedIDs == [base.splits[0].id])
    }

    @Test("Undo Import's shape: imported transactions and the payees they created are deleted, nothing written")
    func undoImportShape() {
        let original = Self.ledger()
        var imported = original
        let kiosk = Payee(name: "Kiosk", createdAt: Self.created)
        imported.payees.append(kiosk)
        let rows = (0..<50)
            .map { index in
                Transaction(
                    amount: Decimal(index + 1),
                    timeZoneID: "Asia/Kolkata",
                    accountID: imported.accounts[0].id,
                    payeeID: kiosk.id,
                )
            }
        imported.transactions += rows
        let changes = LedgerWriteSet(from: imported, to: original)
        #expect(changes.transactions.deleted == Set(rows.map(\.id)))
        #expect(changes.transactions.upserted.isEmpty)
        #expect(changes.payees.deleted == [kiosk.id])
        #expect(changes.payees.upserted.isEmpty)
        #expect(changes.wholeStoreReason == nil)
    }

    @Test("A currency change writes the account's transactions, their splits and its scheduled items again")
    func currencyChange() {
        let base = Self.ledger()
        var target = base
        target.accounts[0].currencyCode = "USD"
        let changes = LedgerWriteSet(from: base, to: target)
        #expect(changes.accounts.upsertedIDs == [base.accounts[0].id])
        #expect(changes.transactions.upsertedIDs == [base.transactions[0].id])
        #expect(changes.splits.upsertedIDs == [base.splits[0].id])
        #expect(changes.scheduledItems.upsertedIDs == [base.scheduledItems[0].id])
        #expect(changes.limits.isEmpty)
    }

    /// D288.1: the item stays, hidden, with its account gone, so its amounts are stored again without that
    /// currency. Its account is a plain id, not a link, so this isn't a dangling link.
    @Test("A deleted account writes its scheduled items again")
    func deletedAccount() {
        let base = Self.ledger()
        var target = base
        target.accounts = []
        target.transactions = []
        target.splits = []
        target.attachments = []
        let changes = LedgerWriteSet(from: base, to: target)
        #expect(changes.accounts.deleted == [base.accounts[0].id])
        #expect(changes.scheduledItems.upsertedIDs == [base.scheduledItems[0].id])
        #expect(changes.wholeStoreReason == nil)
    }

    @Test("A budget's currency change writes its limits again, and a moved limit is written with its new budget")
    func limits() {
        let base = Self.ledger()
        var target = base
        target.budgets[0].currencyCode = "USD"
        var changes = LedgerWriteSet(from: base, to: target)
        #expect(changes.limits.upserted.map(\.id) == base.budgets[0].limits.map(\.id))

        var moved = base
        var second = Budget(name: "Snacks", startDay: Self.day, createdAt: Self.created)
        second.currencyCode = "INR"
        second.limits = moved.budgets[0].limits
        moved.budgets[0].limits = []
        moved.budgets.append(second)
        changes = LedgerWriteSet(from: base, to: moved)
        #expect(changes.limits.upserted.map(\.ownerID) == [second.id])
        #expect(changes.limits.deleted.isEmpty)
        #expect(changes.budgets.upsertedIDs == [base.budgets[0].id, second.id])
    }

    @Test("A new occurrence writes its item and the occurrence, linked to that item")
    func occurrences() {
        let base = Self.ledger()
        var target = base
        let next = ScheduledOccurrence(
            id: UUID(),
            day: CalendarDay(year: 2026, month: 12, day: 1),
            outcome: .posted,
            createdAt: Self.created,
        )
        target.scheduledItems[0].occurrences.append(next)
        var changes = LedgerWriteSet(from: base, to: target)
        #expect(changes.scheduledItems.upsertedIDs == [base.scheduledItems[0].id])
        #expect(changes.occurrences.upserted == [OwnedRecord(value: next, ownerID: base.scheduledItems[0].id)])

        changes = LedgerWriteSet(from: target, to: base)
        #expect(changes.occurrences.deleted == [next.id])
    }

    @Test("A kept value that links to a deleted record goes to the whole-store path")
    func danglingLinks() {
        let base = Self.ledger()
        var target = base
        target.payees = []
        #expect(LedgerWriteSet(from: base, to: target).wholeStoreReason == .danglingReference)

        target = base
        target.categories.removeAll { $0.parentID == nil }
        #expect(LedgerWriteSet(from: base, to: target).wholeStoreReason == .danglingReference)

        target = base
        target.transactions[0].categoryID = UUID()
        #expect(LedgerWriteSet(from: base, to: target).wholeStoreReason == .danglingReference)

        // The scheduled item's payee is a plain id, and nothing else uses this payee.
        target = base
        target.transactions[0].payeeID = nil
        target.scheduledItems[0].payeeID = nil
        target.payees = []
        #expect(LedgerWriteSet(from: base, to: target).wholeStoreReason == nil)
    }

    @Test("Two records with one id go to the whole-store path")
    func duplicates() {
        let base = Self.ledger()
        var target = base
        target.tags.append(base.tags[0])
        #expect(LedgerWriteSet(from: base, to: target).wholeStoreReason == .duplicateIDs)
        #expect(LedgerWriteSet(from: target, to: base).wholeStoreReason == .duplicateIDs)
    }
}
