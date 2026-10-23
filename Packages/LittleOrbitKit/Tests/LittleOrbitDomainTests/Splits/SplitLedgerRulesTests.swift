import Foundation
import LittleOrbitDomain
import Testing

/// The ledger's rules for stored split lines (#34, D64, D97.3, D117.1). Each failure names the rule it broke.
@Suite("Split ledger rules")
struct SplitLedgerRulesTests {
    private let account = Account(name: "Everyday Savings", type: .savings, currencyCode: "INR")
    private let wallet = Account(name: "Pocket Wallet", type: .cash, currencyCode: "INR")
    private let groceries = TransactionCategory(name: "Groceries", kind: .expense)
    private let household = TransactionCategory(name: "Household", kind: .expense)
    private let salary = TransactionCategory(name: "Salary", kind: .income)
    private let now = Date(timeIntervalSinceReferenceDate: 815_000_000)

    private func ledger(
        with transactions: [Transaction],
        categories extra: [TransactionCategory] = [],
    ) throws -> LedgerSnapshot {
        var snapshot = LedgerSnapshot(
            accounts: [account, wallet],
            categories: [groceries, household, salary] + extra,
        )
        for transaction in transactions {
            snapshot = try LedgerBook.savingTransaction(transaction, in: snapshot, now: now)
        }
        return snapshot
    }

    private func expense(_ amount: Decimal, category: UUID? = nil) -> Transaction {
        Transaction(type: .expense, amount: amount, accountID: account.id, categoryID: category)
    }

    private func lines(_ items: (UUID?, Decimal)...) -> [TransactionSplit] {
        items.map { TransactionSplit(categoryID: $0.0, amount: $0.1) }
    }

    /// The rule `splits` on `transaction` break, or nil when they save.
    private func brokenRule(
        _ splits: [TransactionSplit],
        on transaction: Transaction,
        after earlier: [Transaction] = [],
        categories extra: [TransactionCategory] = [],
    ) throws -> SplitRule? {
        let snapshot = try ledger(with: earlier + [transaction], categories: extra)
        do {
            _ = try LedgerBook.replacingSplits(splits, for: transaction.id, in: snapshot, now: now)
            return nil
        } catch LedgerValidationError.splitRuleBroken(let rule) {
            return rule
        }
    }

    @Test("Two lines in different expense categories that add up save")
    func validSplitSaves() throws {
        #expect(try brokenRule(lines((groceries.id, 40), (household.id, 50)), on: expense(90)) == nil)
    }

    @Test("A transfer can't be split")
    func notOnTransfer() throws {
        let transfer = Transaction(type: .transfer, amount: 90, accountID: account.id, transferAccountID: wallet.id)
        #expect(try brokenRule(lines((groceries.id, 40), (household.id, 50)), on: transfer) == .notOnTransfer)
    }

    @Test("A refund can't be split (D97.3, S48)")
    func notOnRefund() throws {
        let original = expense(90, category: groceries.id)
        let refund = Transaction(
            type: .income,
            amount: 50,
            accountID: account.id,
            categoryID: groceries.id,
            refundOfID: original.id,
            isRefund: true,
        )
        #expect(
            try brokenRule(lines((groceries.id, 20), (household.id, 30)), on: refund, after: [original])
                == .notOnRefund
        )
    }

    @Test("A split transaction can't have its own category")
    func transactionHasCategory() throws {
        #expect(
            try brokenRule(lines((groceries.id, 40), (household.id, 50)), on: expense(90, category: groceries.id))
                == .transactionHasCategory
        )
    }

    @Test("One line is too few; 21 are too many; exactly 20 save (D64, S7)")
    func lineCount() throws {
        #expect(try brokenRule(lines((groceries.id, 90)), on: expense(90)) == .tooFewLines)
        let categories = (0..<21).map { TransactionCategory(name: "Line \($0)", kind: .expense) }
        let splits = categories.map { TransactionSplit(categoryID: $0.id, amount: 1) }
        #expect(try brokenRule(splits, on: expense(21), categories: categories) == .tooManyLines)
        #expect(try brokenRule(Array(splits.prefix(20)), on: expense(20), categories: categories) == nil)
    }

    @Test("A ₹0 line is rejected (D64, S3)")
    func lineAmountNotPositive() throws {
        #expect(
            try brokenRule(lines((groceries.id, 90), (household.id, 0)), on: expense(90)) == .lineAmountNotPositive
        )
    }

    @Test("A line with no category is rejected (D64)")
    func lineMissingCategory() throws {
        #expect(try brokenRule(lines((groceries.id, 40), (nil, 50)), on: expense(90)) == .lineMissingCategory)
    }

    @Test("An income category on an expense line is rejected: no mixed splits (D64, S10)")
    func lineCategoryKind() throws {
        #expect(try brokenRule(lines((groceries.id, 40), (salary.id, 50)), on: expense(90)) == .lineCategoryKind)
    }

    @Test("A category on two lines is rejected (D117.1)")
    func categoryRepeated() throws {
        #expect(try brokenRule(lines((groceries.id, 40), (groceries.id, 50)), on: expense(90)) == .categoryRepeated)
    }

    @Test("Lines that don't add up to the total are rejected (D64, S6)")
    func linesDoNotMatchTotal() throws {
        #expect(
            try brokenRule(lines((groceries.id, 40), (household.id, 55)), on: expense(90)) == .linesDoNotMatchTotal
        )
    }

    @Test("Every split rule has its own case, and each test above covers one")
    func everyRuleIsCovered() {
        #expect(SplitRule.allCases.count == 10)
    }
}
