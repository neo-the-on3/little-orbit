import Foundation
import LittleOrbitDomain
import Testing

@Suite("Transaction draft")
struct TransactionDraftTests {
    typealias F = TransactionFixture  // swiftlint:disable:this type_name

    private func draft(_ type: TransactionType = .expense, amount: Decimal = 250) -> TransactionDraft {
        TransactionDraft(
            type: type,
            amount: amount,
            accountID: F.savingsID,
            date: F.date(2026, 10, 20),
            timeZoneID: F.india,
        )
    }

    @Test("Amount must be above 0 (S21)")
    func amount() {
        #expect(draft(amount: 0).issues(accounts: F.accounts) == [.amountMissing])
        #expect(draft().issues(accounts: F.accounts).isEmpty)
    }

    @Test("A transfer needs both accounts, and not the same one twice (AC, S28)")
    func transferAccounts() {
        var transfer = draft(.transfer)
        #expect(transfer.issues(accounts: F.accounts) == [.missingDestination])
        transfer.transferAccountID = F.savingsID
        #expect(transfer.issues(accounts: F.accounts) == [.sameAccount])
        transfer.transferAccountID = F.walletID
        #expect(transfer.issues(accounts: F.accounts).isEmpty)
        #expect(!transfer.needsReceivedAmount(accounts: F.accounts))
    }

    @Test("Cross-currency needs a received amount above 0 (S5, S6)")
    func crossCurrency() {
        var transfer = draft(.transfer, amount: 1_000)
        transfer.transferAccountID = F.usdID
        #expect(transfer.needsReceivedAmount(accounts: F.accounts))
        #expect(transfer.issues(accounts: F.accounts) == [.missingReceived])
        transfer.receivedAmount = 0
        #expect(transfer.issues(accounts: F.accounts) == [.missingReceived])
        transfer.receivedAmount = 12
        #expect(transfer.issues(accounts: F.accounts).isEmpty)
        let saved = transfer.transaction(accounts: F.accounts)
        #expect(saved.destinationAmount == 12)
        #expect(saved.transferAccountID == F.usdID)
        #expect(TransferRate.unitRate(sent: 1_000, received: 12, sourceCurrency: "INR") == Decimal(string: "83.33")!)
    }

    @Test("Same-currency transfers drop any received amount (S8)")
    func sameCurrencyDropsReceived() {
        var transfer = draft(.transfer, amount: 1_500)
        transfer.transferAccountID = F.walletID
        transfer.receivedAmount = 99
        #expect(transfer.transaction(accounts: F.accounts).destinationAmount == nil)
    }

    @Test("Transfers have no category or payee; expenses keep theirs")
    func transferClearsCategory() {
        var transfer = draft(.transfer)
        transfer.transferAccountID = F.walletID
        transfer.categoryID = DefaultCategoryID.food
        transfer.payeeID = UUID()
        let saved = transfer.transaction(accounts: F.accounts)
        #expect(saved.categoryID == nil && saved.payeeID == nil)
        var expense = draft()
        expense.categoryID = DefaultCategoryID.food
        expense.transferAccountID = F.walletID
        let savedExpense = expense.transaction(accounts: F.accounts)
        #expect(savedExpense.categoryID == DefaultCategoryID.food && savedExpense.transferAccountID == nil)
    }

    @Test("Editing keeps the id and creation time, and blank text becomes nil")
    func editKeepsIdentity() {
        let original = F.expense(250, on: F.date(2026, 10, 1))
        var edit = TransactionDraft(editing: original)
        edit.amount = 300
        edit.details = "  "
        let saved = edit.transaction(accounts: F.accounts)
        #expect(saved.id == original.id && saved.createdAt == original.createdAt)
        #expect(saved.amount == 300 && saved.details == nil)
    }

    @Test("Edit offers Expense ↔ Income only, or Transfer only (AC, S36)")
    func typeChanges() {
        #expect(TransactionTypeRules.allowedTypes(editing: nil) == [.expense, .income, .transfer])
        #expect(TransactionTypeRules.allowedTypes(editing: .expense) == [.expense, .income])
        #expect(TransactionTypeRules.allowedTypes(editing: .income) == [.expense, .income])
        #expect(TransactionTypeRules.allowedTypes(editing: .transfer) == [.transfer])
        // D247.2: a refund stays an income.
        #expect(TransactionTypeRules.allowedTypes(editing: .income, isRefund: true) == [.income])
    }

    @Test("Switching to Income clears an expense category; a refund keeps it (S37, S50)")
    func categoryOnTypeChange() {
        let categories = DefaultCategories.make()
        #expect(
            TransactionTypeRules.category(
                DefaultCategoryID.food,
                after: .income,
                categories: categories,
                isRefund: false,
            )
                == nil
        )
        #expect(
            TransactionTypeRules.category(
                DefaultCategoryID.salary,
                after: .income,
                categories: categories,
                isRefund: false,
            )
                == DefaultCategoryID.salary
        )
        #expect(
            TransactionTypeRules.category(
                DefaultCategoryID.shopping,
                after: .income,
                categories: categories,
                isRefund: true,
            )
                == DefaultCategoryID.shopping
        )
        #expect(
            TransactionTypeRules.category(
                DefaultCategoryID.food,
                after: .transfer,
                categories: categories,
                isRefund: false,
            )
                == nil
        )
    }
}
