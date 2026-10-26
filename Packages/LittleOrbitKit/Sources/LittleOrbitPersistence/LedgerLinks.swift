import Foundation
import LittleOrbitDomain

/// The ids a ledger's stored links can point at, for `LedgerWriteSet` (#235): a category's parent, a payee's
/// default category, a transaction's accounts, category, payee and tags, a split's transaction and category,
/// an attachment's transaction, and a budget's categories. These are SwiftData relationships; the other ids a
/// record keeps, such as a scheduled item's account, are plain values.
struct LedgerLinks {
    let accounts: Set<UUID>
    let categories: Set<UUID>
    let payees: Set<UUID>
    let tags: Set<UUID>
    let transactions: Set<UUID>

    init(_ ledger: LedgerSnapshot) {
        accounts = Set(ledger.accounts.map(\.id))
        categories = Set(ledger.categories.map(\.id))
        payees = Set(ledger.payees.map(\.id))
        tags = Set(ledger.tags.map(\.id))
        transactions = Set(ledger.transactions.map(\.id))
    }

    /// Whether a value `changes` writes links to a record `ledger` doesn't have, or a value it leaves alone links
    /// to one it deletes. A value is checked only when it's written, or when a type it links to loses records, so
    /// an ordinary write doesn't go over the whole ledger.
    func hasDanglingLink(in changes: LedgerWriteSet, of ledger: LedgerSnapshot) -> Bool {
        let categoryGone = !changes.categories.deleted.isEmpty
        let transactionGone = !changes.transactions.deleted.isEmpty
        let transactionTargetGone =
            !changes.accounts.deleted.isEmpty || categoryGone || !changes.payees.deleted.isEmpty
            || !changes.tags.deleted.isEmpty
        return dangles(categoryGone ? ledger.categories : changes.categories.upserted, link: categoryLink)
            || dangles(categoryGone ? ledger.payees : changes.payees.upserted, link: payeeLink)
            || dangles(
                transactionTargetGone ? ledger.transactions : changes.transactions.upserted,
                link: transactionLink,
            )
            || dangles(transactionGone || categoryGone ? ledger.splits : changes.splits.upserted, link: splitLink)
            || dangles(transactionGone ? ledger.attachments : changes.attachments.upserted, link: attachmentLink)
            || dangles(categoryGone ? ledger.budgets : changes.budgets.upserted, link: budgetLink)
    }

    private func dangles<Value>(_ values: [Value], link: (Value) -> Bool) -> Bool {
        values.contains { !link($0) }
    }

    private func categoryLink(_ category: TransactionCategory) -> Bool {
        present(category.parentID, in: categories)
    }

    private func payeeLink(_ payee: Payee) -> Bool {
        present(payee.defaultCategoryID, in: categories)
    }

    private func transactionLink(_ transaction: Transaction) -> Bool {
        present(transaction.accountID, in: accounts) && present(transaction.transferAccountID, in: accounts)
            && present(transaction.categoryID, in: categories) && present(transaction.payeeID, in: payees)
            && transaction.tagIDs.allSatisfy(tags.contains)
    }

    private func splitLink(_ split: TransactionSplit) -> Bool {
        present(split.transactionID, in: transactions) && present(split.categoryID, in: categories)
    }

    private func attachmentLink(_ attachment: Attachment) -> Bool {
        present(attachment.transactionID, in: transactions)
    }

    private func budgetLink(_ budget: Budget) -> Bool {
        budget.categoryIDs.allSatisfy(categories.contains)
    }

    private func present(_ id: UUID?, in ids: Set<UUID>) -> Bool {
        id.map(ids.contains) ?? true
    }
}
