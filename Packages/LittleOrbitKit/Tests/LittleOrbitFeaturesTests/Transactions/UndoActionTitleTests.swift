import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// The names the Undo and Redo menus and the shake alert show (Kiran's Q1 on #87: they say exactly what
/// will be undone or redone), and where they say it happened (D198, D166); `name(_:impact:on:)` is the
/// toast's on-screen rule (D165.1). The facts come from the
/// domain's `ChangeImpact`; these rules and words belong to the Features layer.
@Suite("Undo and Redo names")
struct UndoActionTitleTests {
    private func removed(_ count: Int) -> TransactionChange {
        .removed((0..<count).map { _ in RemovedTransaction(transaction: Transaction(type: .expense, amount: 1)) })
    }

    private func replaced(_ count: Int) -> TransactionChange {
        .replaced((0..<count).map { _ in Transaction(type: .expense, amount: 1) })
    }

    @Test("A single change names the action without a count")
    func singular() {
        #expect(UndoActionTitle.base(of: removed(1)) == "Delete Transaction")
        #expect(UndoActionTitle.base(of: TransactionChange.added([UUID()])) == "New Transaction")
        #expect(UndoActionTitle.base(of: replaced(1)) == "Edit Transaction")
    }

    @Test("A bulk change includes the count")
    func plural() {
        #expect(UndoActionTitle.base(of: removed(5)) == "Delete 5 Transactions")
        #expect(UndoActionTitle.base(of: TransactionChange.added([UUID(), UUID()])) == "Add 2 Transactions")
        #expect(UndoActionTitle.base(of: replaced(5)) == "Edit 5 Transactions")
    }

    @Test("Editing one transfer reads \"Edit Transfer\"; several stay transactions (#93)")
    func editTransfer() {
        let transfer = Transaction(type: .transfer, amount: 1, transferAccountID: UUID())
        #expect(UndoActionTitle.base(of: TransactionChange.replaced([transfer])) == "Edit Transfer")
        #expect(UndoActionTitle.base(of: TransactionChange.replaced([transfer, transfer])) == "Edit 2 Transactions")
    }

    @Test("Deleting an account names it: \"Delete Account Household Card\" (#93)")
    func deleteAccount() {
        let household = Account(name: "Household Card", type: .creditCard, currencyCode: "EUR")
        let change = TransactionChange.removedAccount(RemovedAccount(account: household, transactions: []))
        #expect(UndoActionTitle.base(of: change) == "Delete Account Household Card")
    }

    // MARK: - Where (D162, D165.1, D166)

    private let household = Account(name: "Household Card", type: .creditCard, currencyCode: "EUR")
    private let savings = Account(name: "Everyday Savings", type: .savings, currencyCode: "EUR")
    private let rewards = Account(name: "Rewards Card", type: .creditCard, currencyCode: "EUR")
    private let bakery = UUID()

    /// A change to `count` transactions (no transfers) touching `accounts`, before and after.
    private func impact(_ accounts: [Account], count: Int = 1) -> ChangeImpact {
        ChangeImpact(
            accountIDs: Set(accounts.map(\.id)),
            accounts: accounts,
            transactionIDs: (0..<count).map { _ in UUID() },
        )
    }

    /// An edit of one transfer, Household Card → Everyday Savings, that kept its two accounts: the version
    /// before and the current one.
    private var transfer: ChangeImpact {
        let leg = TransferImpact(
            transactionID: bakery,
            sourceAccountID: household.id,
            destinationAccountID: savings.id,
        )
        return ChangeImpact(
            accountIDs: [household.id, savings.id],
            accounts: [household, savings],
            transactionIDs: [bakery],
            transfers: [leg, leg],
        )
    }

    private func name(_ base: String, _ impact: ChangeImpact, on screen: UndoScreen) -> String {
        UndoActionTitle.name(base, impact: impact, on: screen)
    }

    @Test("Only in the account on screen: no account in the name (D165.1)")
    func singleAccountOnScreen() {
        #expect(
            name("Delete 5 Transactions", impact([household], count: 5), on: .account(household.id))
                == "Delete 5 Transactions"
        )
        #expect(name("Delete Transaction", impact([household]), on: .account(household.id)) == "Delete Transaction")
    }

    @Test("Across 2 accounts, viewed from one of them, it still says \"in 2 Accounts\" (D165.1)")
    func multiAccountViewedFromOne() {
        let spread = impact([household, savings], count: 5)
        #expect(
            name("Delete 5 Transactions", spread, on: .account(household.id)) == "Delete 5 Transactions in 2 Accounts"
        )
        #expect(
            name("Delete 5 Transactions", spread, on: .account(savings.id)) == "Delete 5 Transactions in 2 Accounts"
        )
        #expect(UndoActionTitle.isOffScreen(spread, on: .account(household.id)))
    }

    @Test("On another account the name says which one, or how many")
    func onOtherAccount() {
        #expect(
            name("Delete Transaction", impact([household]), on: .account(savings.id))
                == "Delete Transaction in Household Card"
        )
        #expect(
            name("Delete 5 Transactions", impact([household], count: 5), on: .account(savings.id))
                == "Delete 5 Transactions in Household Card"
        )
        #expect(
            name(
                "Delete 5 Transactions",
                impact([household, savings, household], count: 5),
                on: .account(rewards.id),
            )
                == "Delete 5 Transactions in 2 Accounts"
        )
        #expect(name("Delete Transaction", ChangeImpact(), on: .account(savings.id)) == "Delete Transaction")
    }

    @Test("A transfer viewed from either of its accounts: \"Undo Edit Transfer\", no suffix (D166.1)")
    func transferOnEitherSide() {
        #expect(name("Edit Transfer", transfer, on: .account(household.id)) == "Edit Transfer")
        #expect(name("Edit Transfer", transfer, on: .account(savings.id)) == "Edit Transfer")
        #expect(name("Delete Transaction", transfer, on: .account(savings.id)) == "Delete Transaction")
        #expect(!UndoActionTitle.isOffScreen(transfer, on: .account(household.id)))
    }

    @Test("A transfer viewed from another account names both: \"from Household Card to Everyday Savings\" (D166.2)")
    func transferFromElsewhere() {
        #expect(
            name("Edit Transfer", transfer, on: .account(rewards.id))
                == "Edit Transfer from Household Card to Everyday Savings"
        )
        #expect(
            UndoActionTitle.placed("Edit Transfer", transfer)
                == "Edit Transfer from Household Card to Everyday Savings"
        )
        #expect(
            name("Edit Transfer", transfer, on: .list(visible: []))
                == "Edit Transfer from Household Card to Everyday Savings"
        )
        #expect(name("Edit Transfer", transfer, on: .list(visible: [bakery])) == "Edit Transfer")
    }

    @Test("A transfer moved to another account counts every account, before and after (D166.3)")
    func transferChangedAccounts() {
        // Household Card → Everyday Savings, edited to Household Card → Rewards Card.
        let moved = ChangeImpact(
            accountIDs: [household.id, savings.id, rewards.id],
            accounts: [household, savings, rewards],
            transactionIDs: [bakery],
            transfers: [
                TransferImpact(transactionID: bakery, sourceAccountID: household.id, destinationAccountID: savings.id),
                TransferImpact(transactionID: bakery, sourceAccountID: household.id, destinationAccountID: rewards.id),
            ],
        )
        for account in [household, savings, rewards] {
            #expect(name("Edit Transfer", moved, on: .account(account.id)) == "Edit Transfer in 3 Accounts")
        }
    }

    @Test("In a bulk change each transfer counts its own two accounts (D166.4)")
    func bulkWithTransfer() {
        // A transfer Household Card → Everyday Savings and an expense in Household Card.
        let move = UUID()
        let bulk = ChangeImpact(
            accountIDs: [household.id, savings.id],
            accounts: [household, savings],
            transactionIDs: [bakery, move],
            transfers: [
                TransferImpact(transactionID: move, sourceAccountID: household.id, destinationAccountID: savings.id)
            ],
        )
        #expect(
            name("Delete 2 Transactions", bulk, on: .account(household.id)) == "Delete 2 Transactions in 2 Accounts"
        )
        #expect(
            name("Delete 2 Transactions", bulk, on: .account(rewards.id)) == "Delete 2 Transactions in 2 Accounts"
        )
    }

    @Test("A step's name always says where it happened, as one phrase per shape (D198's table)")
    func stepNames() {
        func name(_ change: TransactionChange, _ impact: ChangeImpact) -> String {
            UndoActionTitle.stepName(of: change, impact: impact)
        }
        let one = impact([household])
        #expect(name(.added([UUID()]), one) == "New Transaction in Household Card")
        #expect(name(replaced(1), one) == "Edit Transaction in Household Card")
        #expect(name(removed(1), one) == "Delete Transaction in Household Card")
        #expect(
            name(.added([UUID(), UUID()]), impact([household], count: 2)) == "Add 2 Transactions in Household Card"
        )
        #expect(name(replaced(5), impact([household], count: 5)) == "Edit 5 Transactions in Household Card")
        #expect(name(removed(5), impact([household], count: 5)) == "Delete 5 Transactions in Household Card")
        let spread = impact([household, savings, household], count: 5)
        #expect(name(replaced(5), spread) == "Edit 5 Transactions in 2 Accounts")
        #expect(name(removed(5), spread) == "Delete 5 Transactions in 2 Accounts")
        // An edit that moved one transaction to another account.
        #expect(name(replaced(1), impact([household, savings])) == "Edit Transaction in 2 Accounts")
        // A change that touched no account keeps the plain name.
        #expect(name(removed(1), ChangeImpact()) == "Delete Transaction")
    }

    @Test("A transfer names both accounts on every screen; moved, it counts them (D198, D166.2, D166.3)")
    func transferStepNames() {
        let leg = Transaction(id: bakery, type: .transfer, amount: 1, transferAccountID: savings.id)
        #expect(
            UndoActionTitle.stepName(of: .added([bakery]), impact: transfer)
                == "New Transfer from Household Card to Everyday Savings"
        )
        #expect(
            UndoActionTitle.stepName(of: .replaced([leg]), impact: transfer)
                == "Edit Transfer from Household Card to Everyday Savings"
        )
        #expect(
            UndoActionTitle.stepName(of: .removed([RemovedTransaction(transaction: leg)]), impact: transfer)
                == "Delete Transfer from Household Card to Everyday Savings"
        )
        let moved = ChangeImpact(
            accountIDs: [household.id, savings.id, rewards.id],
            accounts: [household, savings, rewards],
            transactionIDs: [bakery],
            transfers: [
                TransferImpact(transactionID: bakery, sourceAccountID: household.id, destinationAccountID: savings.id),
                TransferImpact(transactionID: bakery, sourceAccountID: household.id, destinationAccountID: rewards.id),
            ],
        )
        #expect(UndoActionTitle.stepName(of: .replaced([leg]), impact: moved) == "Edit Transfer in 3 Accounts")
    }

    @Test("Deleting an account keeps its name, which already says which account (D198)")
    func accountStepName() {
        let change = TransactionChange.removedAccount(RemovedAccount(account: household, transactions: []))
        #expect(UndoActionTitle.stepName(of: change, impact: impact([household])) == "Delete Account Household Card")
    }

    @Test("On a combined list, the account is left off only while every transaction is visible in it")
    func onCombinedList() {
        let one = ChangeImpact(accountIDs: [household.id], accounts: [household], transactionIDs: [bakery])
        #expect(name("Edit Transaction", one, on: .list(visible: [bakery])) == "Edit Transaction")
        #expect(name("Edit Transaction", one, on: .list(visible: [UUID()])) == "Edit Transaction in Household Card")
        #expect(name("Edit Transaction", one, on: .list(visible: [])) == "Edit Transaction in Household Card")
        let two = impact([household, savings], count: 2)
        let partly = Set([two.transactionIDs[0]])
        #expect(
            name("Delete 2 Transactions", two, on: .list(visible: partly)) == "Delete 2 Transactions in 2 Accounts"
        )
    }

    @Test("Off-screen: the same rule, for the undo notice")
    func offScreen() {
        let one = impact([household])
        #expect(!UndoActionTitle.isOffScreen(one, on: .account(household.id)))
        #expect(UndoActionTitle.isOffScreen(one, on: .account(savings.id)))
        #expect(!UndoActionTitle.isOffScreen(one, on: .list(visible: [one.transactionIDs[0]])))
        #expect(UndoActionTitle.isOffScreen(one, on: .list(visible: [])))
    }

    @Test("A route needs one transfer that kept its two accounts, and both accounts still there")
    func route() {
        #expect(UndoActionTitle.route(of: transfer)?.source.id == household.id)
        #expect(UndoActionTitle.route(of: transfer)?.destination.id == savings.id)
        var gone = transfer
        gone.accounts = [household]
        #expect(UndoActionTitle.route(of: gone) == nil)
        #expect(UndoActionTitle.placed("Edit Transfer", gone) == "Edit Transfer in Household Card")
        #expect(UndoActionTitle.route(of: impact([household, savings])) == nil)
    }
}
