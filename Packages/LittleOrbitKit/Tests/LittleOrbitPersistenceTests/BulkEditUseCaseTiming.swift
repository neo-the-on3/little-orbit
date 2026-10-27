import Foundation
import LittleOrbitDomain

/// #285, D398: the Bulk Edit that Tester2's N5 times (6434969976), through the use cases rather than the
/// repository alone: 3,334 of 10,000 transactions given another account, an existing payee and a description,
/// with every rule checked, then undone and redone. The ledger is shaped like the #235 timing store: two accounts,
/// 20 categories, 300 payees, 4 tags, some rows tagged and some split.
enum BulkEditUseCaseTiming {
    static let existing = 10_000
    static let selected = 3_334
    static let zone = "Asia/Kolkata"
    /// D398: Apply, Undo and Redo each within 2.0 s.
    static let bound: Duration = .seconds(2)

    static func ledger() -> LedgerSnapshot {
        let savings = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR", sortOrder: 1)
        let card = Account(name: "Rewards Card", type: .creditCard, currencyCode: "INR", sortOrder: 2)
        let categories = (0..<20)
            .map { TransactionCategory(name: "Spend \($0)", kind: .expense, sortOrder: Double($0)) }
        let payees = (0..<300).map { Payee(name: "Shop \($0)") }
        let tags = (0..<4).map { Tag(name: "Tag \($0)", sortOrder: Double($0)) }
        var transactions: [Transaction] = []
        var splits: [TransactionSplit] = []
        transactions.reserveCapacity(existing)
        for index in 0..<existing {
            let isSplit = index.isMultiple(of: 200)
            let transaction = Transaction(
                type: isSplit || !index.isMultiple(of: 5) ? .expense : .income,
                amount: Decimal(index % 700 + 2),
                date: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 3600),
                timeZoneID: zone,
                accountID: index.isMultiple(of: 2) ? savings.id : card.id,
                // A split row is uncategorised; its splits hold the categories.
                categoryID: isSplit || index.isMultiple(of: 5) ? nil : categories[index % categories.count].id,
                payeeID: payees[index % payees.count].id,
                details: "Existing \(index)",
                tagIDs: index.isMultiple(of: 25) ? [tags[index % tags.count].id] : [],
            )
            transactions.append(transaction)
            if isSplit {
                splits.append(TransactionSplit(transactionID: transaction.id, categoryID: categories[0].id, amount: 1))
                splits.append(
                    TransactionSplit(
                        transactionID: transaction.id,
                        categoryID: categories[1].id,
                        amount: transaction.amount - 1,
                        sortOrder: 1,
                    )
                )
            }
        }
        return LedgerSnapshot(
            accounts: [savings, card],
            transactions: transactions,
            categories: categories,
            payees: payees,
            tags: tags,
            splits: splits,
        )
    }

    /// Every third stored transaction: to the Rewards Card, payee "Shop 7", description "Bulk edit".
    @MainActor
    static func request(in repository: any LedgerRepository) throws -> BulkEditRequest {
        let stored = try repository.transactions()
        let selection = stored.indices.filter { $0.isMultiple(of: 3) }.map { stored[$0] }
        let accounts = try repository.accounts()
        var changes = BulkEditChanges()
        changes.accountID = accounts.first { $0.name == "Rewards Card" }?.id
        changes.payeeID = .some(nil)
        changes.details = .some("Bulk edit")
        return BulkEditRequest(
            selection: selection,
            changes: changes,
            payeeName: "Shop 7",
            accounts: accounts,
            timeZoneID: zone,
            now: Date(timeIntervalSince1970: 1_800_000_000),
        )
    }

    struct Timing {
        let apply: Duration
        let undo: Duration
        let redo: Duration
        let selected: Int
        /// The descriptions after Apply, Undo and Redo, to check each did its work.
        let details: [Set<String?>]
    }

    /// Apply, with what recording its Undo step reads (its impact and outcome), then Undo and Redo, each timed.
    /// Each runs the batch path wholly on the main actor (`apply(_:)`, `revert(_:expecting:)`), the most it can
    /// block it, and so that no other test's main-actor work lands in a measured hop off it and back.
    @MainActor
    static func run(on repository: any LedgerRepository) throws -> Timing {
        let request = try request(in: repository)
        let ids = Set(request.selection.map(\.id))
        let apply = DefaultApplyBulkEditUseCase(repository: repository)
        let changes = DefaultTransactionChangesUseCase(repository: repository)
        let clock = ContinuousClock()
        func details() throws -> Set<String?> {
            Set(try repository.transactions().filter { ids.contains($0.id) }.map(\.details))
        }

        var start = clock.now
        let change = try apply.apply(request)
        _ = try changes.impact(of: change)
        let outcome = try changes.outcome(of: change)
        let applyTime = clock.now - start
        let applied = try details()

        start = clock.now
        guard case .reverted(let inverse, let undone) = try changes.revert(change, expecting: outcome) else {
            throw StaleRun()
        }
        let undoTime = clock.now - start
        let afterUndo = try details()

        start = clock.now
        guard case .reverted = try changes.revert(inverse, expecting: undone) else {
            throw StaleRun()
        }
        let redoTime = clock.now - start
        return Timing(
            apply: applyTime,
            undo: undoTime,
            redo: redoTime,
            selected: ids.count,
            details: [applied, afterUndo, try details()],
        )
    }

    struct StaleRun: Error {}
}
