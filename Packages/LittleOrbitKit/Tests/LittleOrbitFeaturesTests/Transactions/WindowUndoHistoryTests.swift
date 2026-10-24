import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// One window's undo history (#93: D161, D161.2, D162, D164, D187). Undo outlives the screen that made the
/// change (Tester's #87 B1), names exactly what it will change, and says where when that isn't on screen.
/// The two-window cases are in `WindowUndoTwoWindowTests`.
@MainActor
@Suite("Window undo history")
struct WindowUndoHistoryTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    @MainActor
    struct Setup {
        let repository: InMemoryLedgerRepository
        let useCases: TransactionUseCases
        let window: TestWindow
        var history: WindowUndoHistory { window.history }
    }

    static func setup(_ transactions: [Transaction] = []) throws -> Setup {
        let repository = try F.repository(transactions)
        let useCases = TransactionUseCases(repository: repository, categoryNames: CatalogDefaultCategoryNames())
        return Setup(repository: repository, useCases: useCases, window: TestWindow(useCases))
    }

    private func setup(_ transactions: [Transaction] = []) throws -> Setup {
        try Self.setup(transactions)
    }

    /// The app's one account delete (#93), as the accounts screens run it.
    static func deleteAccount(_ repository: InMemoryLedgerRepository, _ id: UUID) throws -> TransactionChange {
        .removedAccount(try AccountUseCases(repository: repository).deleteAccount.delete(id))
    }

    private func balance(_ setup: Setup, _ accountID: UUID) throws -> Decimal {
        try setup.repository.balance(of: accountID, today: F.today)
    }

    @Test("Delete, leave the screen, then Undo restores the transaction and its balance; Redo deletes it again")
    func undoAfterScreenIsGone() throws {
        let lunch = F.expense(250, on: F.date(2026, 10, 20, 9), details: "Team lunch")
        let setup = try setup([lunch])
        let before = try balance(setup, F.savingsID)
        var history: AccountHistoryViewModel? = AccountHistoryViewModel(
            useCases: setup.useCases,
            accountID: F.savingsID,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
        weak let released = history
        history?.load()
        setup.history.setScreen(.account(F.savingsID))
        let change = try #require(history?.delete(id: lunch.id))
        setup.history.record(change)
        history = nil
        #expect(released == nil)

        #expect(setup.history.undoTitle == "Delete Transaction in Everyday Savings")
        setup.history.undo()
        #expect(setup.window.announcements == ["Undid Delete Transaction in Everyday Savings"])
        #expect(try setup.repository.transactions().map(\.details) == ["Team lunch"])
        #expect(try balance(setup, F.savingsID) == before)
        #expect(setup.history.redoTitle == "Delete Transaction in Everyday Savings")
        #expect(setup.history.undoTitle == nil)

        setup.history.redo()
        #expect(setup.window.announcements.last == "Redid Delete Transaction in Everyday Savings")
        #expect(try setup.repository.transactions().isEmpty)
        #expect(setup.history.undoTitle == "Delete Transaction in Everyday Savings")
    }

    @Test(
        "New, New Transfer, Edit, Edit Transfer and bulk Edit keep the user's name, with where it happened, through Undo and Redo"
    )
    func names() throws {
        let lunch = F.expense(250, on: F.date(2026, 10, 18))
        let move = F.transfer(500, on: F.date(2026, 10, 19), from: F.savingsID, to: F.walletID)
        let setup = try setup([lunch, move])
        let history = setup.history
        history.setScreen(.account(F.savingsID))
        func cycle(_ change: TransactionChange, _ name: String) {
            history.record(change)
            #expect(history.undoTitle == name)
            history.undo()
            #expect(history.redoTitle == name)
            history.redo()
            #expect(history.undoTitle == name)
            #expect(setup.window.announcements.suffix(2) == ["Undid \(name)", "Redid \(name)"])
        }
        cycle(
            try setup.useCases.saveTransactions.save([F.expense(10, on: F.date(2026, 10, 20, 8))]),
            "New Transaction in Everyday Savings",
        )
        cycle(
            try setup.useCases.saveTransactions.save([
                F.transfer(70, on: F.date(2026, 10, 20, 9), from: F.savingsID, to: F.walletID)
            ]),
            "New Transfer from Everyday Savings to Corner Wallet",
        )
        var edited = try #require(try setup.repository.transactions().first { $0.id == lunch.id })
        edited.amount = 300
        cycle(try setup.useCases.saveTransactions.save([edited]), "Edit Transaction in Everyday Savings")
        var movedMore = try #require(try setup.repository.transactions().first { $0.id == move.id })
        movedMore.amount = 600
        cycle(
            try setup.useCases.saveTransactions.save([movedMore]),
            "Edit Transfer from Everyday Savings to Corner Wallet",
        )
    }

    @Test("Bulk delete is one step: \"Undo Delete 5 Transactions\" restores all 5 and every balance")
    func bulkDelete() throws {
        let items = (0..<5).map { F.expense(Decimal(10 * ($0 + 1)), on: F.date(2026, 10, 10 + $0)) }
        let setup = try setup(items)
        let before = try balance(setup, F.savingsID)
        setup.history.setScreen(.account(F.savingsID))
        setup.history.record(try setup.useCases.changes.remove(ids: items.map(\.id)))
        #expect(setup.history.undoTitle == "Delete 5 Transactions in Everyday Savings")
        setup.history.undo()
        #expect(Set(try setup.repository.transactions().map(\.id)) == Set(items.map(\.id)))
        #expect(try balance(setup, F.savingsID) == before)
        #expect(setup.history.redoTitle == "Delete 5 Transactions in Everyday Savings")
        setup.history.redo()
        #expect(try setup.repository.transactions().isEmpty)
    }

    @Test("W2: one history across a window's accounts; the newest change is undone first, from any screen")
    func oneHistoryPerWindow() throws {
        let lunch = F.expense(250, on: F.date(2026, 10, 18))
        let fuel = F.expense(900, on: F.date(2026, 10, 18), account: F.cardID)
        let setup = try setup([lunch, fuel])
        let history = setup.history
        history.record(try setup.useCases.changes.remove(ids: [lunch.id]))
        history.record(try setup.useCases.changes.remove(ids: [fuel.id]))
        history.setScreen(.account(F.walletID))

        #expect(history.undoTitle == "Delete Transaction in Rewards Card")
        history.undo()
        #expect(try setup.repository.transactions().map(\.id) == [fuel.id])
        #expect(history.undoTitle == "Delete Transaction in Everyday Savings")
        history.undo()
        #expect(Set(try setup.repository.transactions().map(\.id)) == [lunch.id, fuel.id])
        #expect(!history.canUndo)
    }

    @Test("Undo names the account when it isn't on screen: one account, several, or a combined list (D162)")
    func namesAcrossAccounts() throws {
        let items = (0..<5).map { F.expense(Decimal($0 + 1), on: F.date(2026, 10, 10 + $0), account: F.cardID) }
        let mixed = [
            F.expense(1, on: F.date(2026, 10, 1)), F.expense(2, on: F.date(2026, 10, 2), account: F.cardID),
        ]
        let setup = try setup(items + mixed)
        let history = setup.history
        history.setScreen(.account(F.savingsID))
        history.record(try setup.useCases.changes.remove(ids: [items[0].id]))
        #expect(history.undoTitle == "Delete Transaction in Rewards Card")
        history.record(try setup.useCases.changes.remove(ids: items.dropFirst().map(\.id)))
        #expect(history.undoTitle == "Delete 4 Transactions in Rewards Card")
        history.record(try setup.useCases.changes.remove(ids: mixed.map(\.id)))
        history.setScreen(.account(F.walletID))
        #expect(history.undoTitle == "Delete 2 Transactions in 2 Accounts")

        // The name is the same on every screen, including one of the 2 accounts and a list that shows every
        // transaction (D198).
        history.setScreen(.account(F.cardID))
        #expect(history.undoTitle == "Delete 2 Transactions in 2 Accounts")
        history.setScreen(.list(visible: [mixed[0].id]))
        #expect(history.undoTitle == "Delete 2 Transactions in 2 Accounts")
        history.setScreen(.list(visible: Set(mixed.map(\.id))))
        #expect(history.undoTitle == "Delete 2 Transactions in 2 Accounts")
        history.setScreen(.list(visible: []))
        #expect(history.undoTitle == "Delete 2 Transactions in 2 Accounts")
    }

    @Test(
        "The toast leaves the account out only when every affected account is on screen; Undo and Redo always say it (D165.1, D198)"
    )
    func everyAccountOnScreen() throws {
        let card = (0..<5).map { F.expense(Decimal($0 + 1), on: F.date(2026, 10, 10 + $0), account: F.cardID) }
        let spread =
            (0..<3).map { F.expense(Decimal($0 + 1), on: F.date(2026, 10, 1 + $0), account: F.cardID) }
            + (0..<2).map { F.expense(Decimal($0 + 1), on: F.date(2026, 10, 5 + $0)) }
        let setup = try setup(card + spread)
        let history = setup.history

        // 5 only in Rewards Card, viewed there: the toast leaves the account off, the Undo name doesn't.
        history.setScreen(.account(F.cardID))
        let single = history.record(try setup.useCases.changes.remove(ids: card.map(\.id)))
        #expect(history.undoTitle == "Delete 5 Transactions in Rewards Card")
        history.showToast("5 transactions deleted", for: single)
        #expect(history.toast?.message == "5 transactions deleted")
        // The same 5, viewed from another account: the same name.
        history.setScreen(.account(F.savingsID))
        #expect(history.undoTitle == "Delete 5 Transactions in Rewards Card")

        // 5 across Rewards Card and Everyday Savings: "in 2 Accounts" everywhere, the toast too.
        let both = history.record(try setup.useCases.changes.remove(ids: spread.map(\.id)))
        #expect(history.undoTitle == "Delete 5 Transactions in 2 Accounts")
        history.setScreen(.account(F.cardID))
        #expect(history.undoTitle == "Delete 5 Transactions in 2 Accounts")
        history.showToast("5 transactions deleted", for: both)
        #expect(history.toast?.message == "5 transactions deleted in 2 Accounts")
        history.undo()
        #expect(history.redoTitle == "Delete 5 Transactions in 2 Accounts")
    }

    @Test("A transfer: Undo and Redo always name both accounts; the toast leaves them off on either one (D166, D198)")
    func transferTitles() throws {
        let move = F.transfer(500, on: F.date(2026, 10, 18), from: F.savingsID, to: F.cardID)
        let setup = try setup([move])
        let history = setup.history
        history.setScreen(.account(F.savingsID))

        var edited = try #require(try setup.repository.transactions().first)
        edited.amount = 600
        history.record(try setup.useCases.saveTransactions.save([edited]))
        #expect(history.undoTitle == "Edit Transfer from Everyday Savings to Rewards Card")
        history.setScreen(.account(F.walletID))
        #expect(history.undoTitle == "Edit Transfer from Everyday Savings to Rewards Card")
        history.undo()
        #expect(history.redoTitle == "Edit Transfer from Everyday Savings to Rewards Card")
        #expect(history.notice?.message == "Updated 1 transaction from Everyday Savings to Rewards Card")
        history.redo()

        // Moved to Corner Wallet: every account before and after counts (D166.3).
        var moved = try #require(try setup.repository.transactions().first)
        moved.transferAccountID = F.walletID
        history.record(try setup.useCases.saveTransactions.save([moved]))
        #expect(history.undoTitle == "Edit Transfer in 3 Accounts")
        history.setScreen(.account(F.savingsID))
        #expect(history.undoTitle == "Edit Transfer in 3 Accounts")

        let step = history.record(try setup.useCases.changes.remove(ids: [move.id]))
        #expect(history.undoTitle == "Delete Transfer from Everyday Savings to Corner Wallet")
        history.showToast("Deleted transfer", for: step)
        #expect(history.toast?.message == "Deleted transfer")
        history.setScreen(.account(F.usdID))
        history.showToast("Deleted transfer", for: step)
        #expect(history.toast?.message == "Deleted transfer from Everyday Savings to Corner Wallet")
    }

    @Test("X8: a failed Undo changes nothing, says so, and keeps the step to try again")
    func failedUndo() {
        let fake = FakeTransactionUseCases()
        let window = TestWindow(fake.useCases)
        window.history.record(.removed([RemovedTransaction(transaction: Transaction(type: .expense, amount: 1))]))
        fake.revertError = FakeTransactionUseCases.Failure()
        window.history.undo()
        #expect(window.history.alert?.title == "Couldn’t Undo Delete Transaction")
        #expect(fake.reverted.isEmpty)
        window.settle()
        #expect(window.history.undoTitle == "Delete Transaction", "The step is back")
        #expect(!window.history.canRedo)
        fake.revertError = nil
        window.history.dismissAlert()
        window.history.undo()
        #expect(fake.reverted.count == 1)
        #expect(window.history.alert == nil)
        #expect(window.history.redoTitle == "Delete Transaction")
    }

    @Test("A failed Redo keeps the step on Redo, to try again")
    func failedRedo() {
        let fake = FakeTransactionUseCases()
        let window = TestWindow(fake.useCases)
        window.history.record(.removed([RemovedTransaction(transaction: Transaction(type: .expense, amount: 1))]))
        window.history.undo()
        fake.revertError = FakeTransactionUseCases.Failure()
        window.history.redo()
        #expect(window.history.alert?.title == "Couldn’t Redo Delete Transaction")
        window.settle()
        #expect(window.history.redoTitle == "Delete Transaction")
        #expect(!window.history.canUndo)
        fake.revertError = nil
        window.history.dismissAlert()
        window.history.redo()
        #expect(window.history.undoTitle == "Delete Transaction")
    }

    @Test("If the accounts can't be read, the step still records and the history says so")
    func unreadablePlace() {
        let fake = FakeTransactionUseCases()
        fake.impactError = FakeTransactionUseCases.Failure()
        let window = TestWindow(fake.useCases)
        window.history.record(.removed([RemovedTransaction(transaction: Transaction(type: .expense, amount: 1))]))
        #expect(window.history.undoTitle == "Delete Transaction")
        // D204: its own title, never a failed Undo's or Redo's.
        #expect(window.history.alert?.title == "Couldn’t Make the Change")
        #expect(
            window.history.alert?.message == "Couldn’t read your accounts, so Undo may not say where this change was."
        )
        window.history.dismissAlert()
        #expect(window.history.alert == nil)
    }

    @Test("Deleting an account replaces this window's steps for it with \"Undo Delete Account …\" (D187.9)")
    func deleteAccount() throws {
        let lunch = F.expense(250, on: F.date(2026, 10, 18))
        let items = (0..<12).map { F.expense(Decimal($0 + 1), on: F.date(2026, 10, 1 + $0), account: F.cardID) }
        let setup = try setup([lunch] + items)
        let history = setup.history
        history.setScreen(.list(visible: []))
        history.record(try setup.useCases.changes.remove(ids: [lunch.id]))
        history.record(try setup.useCases.changes.remove(ids: [items[0].id]))
        var edited = try #require(try setup.repository.transactions().first { $0.id == items[1].id })
        edited.amount = 99
        history.record(try setup.useCases.saveTransactions.save([edited]))

        history.record(try Self.deleteAccount(setup.repository, F.cardID))
        #expect(history.undoTitle == "Delete Account Rewards Card")
        #expect(setup.window.undoManager.undoCount == 2, "The card's own steps are gone from the UndoManager")
        history.undo()
        #expect(try setup.repository.accounts().contains { $0.id == F.cardID })
        #expect(try setup.repository.transactions().filter { $0.accountID == F.cardID }.count == 11)
        #expect(history.redoTitle == "Delete Account Rewards Card")
        #expect(history.undoTitle == "Delete Transaction in Everyday Savings")
        history.undo()
        #expect(!history.canUndo)
    }
}

extension WindowUndoHistoryTests {
    // MARK: - Toast (D164.2) and off-screen notice (D164.3, D187.6)

    private func deleted(_ setup: Setup, _ ids: [UUID]) throws -> UUID {
        setup.history.record(try setup.useCases.changes.remove(ids: ids))
    }

    @Test("The toast's Undo is the same step as the toolbar Undo, and Redo offers it back")
    func toastUndo() throws {
        let lunch = F.expense(250, on: F.date(2026, 10, 18))
        let setup = try setup([lunch])
        setup.history.setScreen(.account(F.savingsID))
        let step = try deleted(setup, [lunch.id])
        setup.history.showToast("Deleted Team lunch −₹250.00", for: step)
        #expect(setup.history.toast?.message == "Deleted Team lunch −₹250.00")
        setup.history.undoToast()
        #expect(setup.window.announcements == ["Undid Delete Transaction in Everyday Savings"])
        #expect(setup.history.toast == nil)
        #expect(try setup.repository.transactions().map(\.id) == [lunch.id])
        #expect(setup.history.redoTitle == "Delete Transaction in Everyday Savings")
    }

    @Test("Any other undoable action closes the toast, so its Undo never reverses something else")
    func toastCloses() throws {
        let lunch = F.expense(250, on: F.date(2026, 10, 18))
        let tea = F.expense(20, on: F.date(2026, 10, 18))
        let setup = try setup([lunch, tea])
        let history = setup.history
        history.setScreen(.account(F.savingsID))
        let first = try deleted(setup, [lunch.id])
        history.showToast("Deleted lunch", for: first)
        _ = try deleted(setup, [tea.id])
        #expect(history.toast == nil)
        // A stale toast can't be shown for an older step either.
        history.showToast("Deleted lunch", for: first)
        #expect(history.toast == nil)

        history.undo()
        history.redo()
        #expect(setup.window.announcements.last == "Redid Delete Transaction in Everyday Savings")
        history.showToast("Deleted tea", for: UUID())
        #expect(history.toast == nil)
        let step = history.record(try setup.useCases.saveTransactions.save([F.expense(5, on: F.now)]))
        history.showToast("Added", for: step)
        history.undo()
        #expect(history.toast == nil, "Undo closes it")
    }

    @Test("W5: typing in a field is undone first; the toast's Undo then reverses nothing")
    func typingComesFirst() throws {
        let lunch = F.expense(250, on: F.date(2026, 10, 18))
        let setup = try setup([lunch])
        setup.history.setScreen(.account(F.savingsID))
        let step = try deleted(setup, [lunch.id])
        setup.history.showToast("Deleted lunch", for: step)
        setup.window.undoManager.registerTyping()
        #expect(setup.history.undoTitle == "Typing")
        setup.history.undoToast()
        #expect(setup.history.toast == nil)
        #expect(try setup.repository.transactions().isEmpty, "The toast didn't undo the typing or the delete")
        setup.history.undo()
        #expect(try setup.repository.transactions().isEmpty, "The typing went first")
        #expect(setup.history.undoTitle == "Delete Transaction in Everyday Savings")
        setup.history.undo()
        #expect(try setup.repository.transactions().map(\.id) == [lunch.id])
    }

    @Test("Toast wording: one row with its amount, or a count, plus the account when it's off screen")
    func toastWording() {
        let bakery = (title: "Corner Bakery", amount: "−€4.50")
        #expect(UndoToast.message(single: bakery, count: 1, place: nil) == "Deleted Corner Bakery −€4.50")
        #expect(UndoToast.message(single: nil, count: 5, place: nil) == "5 transactions deleted")
        #expect(
            UndoToast.message(single: bakery, count: 1, place: "in Household Card")
                == "Deleted Corner Bakery −€4.50 in Household Card"
        )
    }

    @Test("A signed amount in the toast is its own unit, so the line breaks around it (D169, D170 U2)")
    func toastFigure() throws {
        let lunch = F.expense(250, on: F.date(2026, 10, 18))
        let setup = try setup([lunch])
        setup.history.setScreen(.account(F.cardID))
        let step = try deleted(setup, [lunch.id])
        setup.history.showToast("Deleted Income +₹250.00", figure: "+₹250.00", for: step)
        let toast = try #require(setup.history.toast)
        #expect(toast.message == "Deleted Income +₹250.00 in Everyday Savings")
        #expect(
            toast.figureParts
                == AccountSubtitle.FigureParts(
                    before: "Deleted Income",
                    figure: "+₹250.00",
                    after: "in Everyday Savings",
                )
        )
        setup.history.showToast("5 transactions deleted", for: step)
        #expect(setup.history.toast?.figureParts == nil)
    }

    @Test("Deleting an account shows its toast, and the toast's Undo restores it in one step (D170 U3)")
    func accountDeleteToast() throws {
        let items = (0..<3).map { F.expense(Decimal($0 + 1), on: F.date(2026, 10, 1 + $0), account: F.cardID) }
        let setup = try setup(items)
        let history = setup.history
        history.setScreen(.list(visible: []))
        let step = history.record(try Self.deleteAccount(setup.repository, F.cardID))
        history.showToast(UndoToast.message(deletedAccount: "Rewards Card"), for: step)
        #expect(history.toast?.message == "Deleted “Rewards Card”")
        history.undoToast()
        #expect(setup.window.announcements == ["Undid Delete Account Rewards Card"])
        #expect(history.toast == nil)
        #expect(try setup.repository.accounts().contains { $0.id == F.cardID })
        #expect(try setup.repository.transactions().count == 3)
        #expect(history.redoTitle == "Delete Account Rewards Card")
    }

    @Test("N2: Undo of a change in another account shows \"Restored 5 transactions in …\" with Show")
    func offScreenNotice() throws {
        let items = (0..<5).map { F.expense(Decimal($0 + 1), on: F.date(2026, 10, 10 + $0), account: F.cardID) }
        let setup = try setup(items)
        let history = setup.history
        history.setScreen(.account(F.cardID))
        _ = try deleted(setup, items.map(\.id))
        history.setScreen(.account(F.savingsID))
        history.undo()
        #expect(history.notice?.message == "Restored 5 transactions in Rewards Card")
        #expect(history.notice?.accountID == F.cardID)

        history.setScreen(.account(F.cardID))
        history.redo()
        #expect(history.notice == nil, "On screen: no notice")
        history.setScreen(.list(visible: []))
        history.undo()
        #expect(history.notice?.message == "Restored 5 transactions in Rewards Card")
        history.dismissNotice()
        #expect(history.notice == nil)
    }

    @Test("N1: Undo in the account on screen shows no notice, even if the row scrolled away; VoiceOver hears it")
    func onScreenNoNotice() throws {
        let lunch = F.expense(250, on: F.date(2026, 10, 18))
        let setup = try setup([lunch])
        setup.history.setScreen(.account(F.savingsID))
        var edited = try #require(try setup.repository.transactions().first)
        edited.amount = 300
        setup.history.record(try setup.useCases.saveTransactions.save([edited]))
        setup.history.undo()
        #expect(setup.history.notice == nil)
        #expect(setup.window.announcements == ["Undid Edit Transaction in Everyday Savings"])
    }

    @Test("Undoing an account delete elsewhere says \"Restored Rewards Card\" and Show goes there")
    func accountNotice() throws {
        let setup = try setup([F.expense(1, on: F.date(2026, 10, 10), account: F.cardID)])
        setup.history.record(try Self.deleteAccount(setup.repository, F.cardID))
        setup.history.setScreen(.list(visible: []))
        setup.history.undo()
        #expect(setup.history.notice?.message == "Restored Rewards Card")
        #expect(setup.history.notice?.accountID == F.cardID)
        setup.history.redo()
        #expect(setup.history.notice?.message == "Deleted Rewards Card")
        #expect(setup.history.notice?.accountID == nil)
    }
}
