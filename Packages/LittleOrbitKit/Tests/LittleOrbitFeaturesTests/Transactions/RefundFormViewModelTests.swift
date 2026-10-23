import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// The refund sheet on iOS and macOS ⌘R (#34; D33, D35, D65, D97.4, D234.4, D235), with #34's own sample data.
/// Names, dates and amounts are made up.
@MainActor
@Suite("Refund sheet")
struct RefundFormViewModelTests {
    typealias F = RefundsFeatureFixture  // swiftlint:disable:this type_name

    private static let expenseDate = F.date(2026, 10, 17, zone: F.kolkata)

    private func sheet(_ expense: Transaction, in fixture: F) -> RefundFormViewModel {
        RefundFormViewModel(
            refunds: DefaultRefundTransactionUseCase(repository: fixture.repository),
            dates: fixture.useCases.dates,
            expenseID: expense.id,
            locale: Locale(identifier: "en_IN"),
            timeZone: TimeZone(identifier: F.kolkata)!,
            now: { F.now },
        )
    }

    private func stored(_ id: UUID, in fixture: F) throws -> Transaction? {
        try fixture.repository.transactions().first { $0.id == id }
    }

    @Test("S14, D234.4: ₹700.00 of ₹1,000.00, the expense's account, category and payee, dated today")
    func prefilled() throws {
        let fixture = try F()
        let trailhead = try fixture.payee("Trailhead Sports")
        let expense = try fixture.expense(1_000, on: Self.expenseDate, payee: trailhead)
        try fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        let model = sheet(expense, in: fixture)
        #expect(model.isAvailable)
        #expect(model.amountText == "700.00")
        #expect(model.accountID == fixture.savings.id)
        #expect(model.categoryName == "Shopping")
        #expect(model.payeeText == "Trailhead Sports")
        #expect(model.ownDay == CalendarDay(year: 2026, month: 10, day: 23))
        #expect(model.refundOfText == "Trailhead Sports · 17 Oct")
        #expect(model.refundableText == "₹700.00 of ₹1,000.00")
        #expect(
            model.footnote
                == "₹300.00 has already been refunded. A refund keeps the expense’s category and uses the same currency."
        )
        #expect(model.caption == "Refund of Trailhead Sports · 17 Oct 2026 · ₹1,000.00 · ₹300.00 already refunded")
        #expect(model.amountSuffix == "of ₹700.00 refundable")
        #expect(model.categoryFromExpenseText == "Shopping (from the expense)")
        #expect(model.messages.isEmpty)
        #expect(model.canSave)
    }

    @Test("P31.4: no payee on the expense, or one whose record is gone, starts with none")
    func noPayee() throws {
        let fixture = try F()
        let plain = try fixture.expense(1_000, on: Self.expenseDate, details: "  Running shoes ")
        let gonePayee = try fixture.payee("Pinewood Pharmacy")
        let orphaned = try fixture.expense(400, on: Self.expenseDate, payee: gonePayee)
        try fixture.repository.deletePayee(id: gonePayee.id)
        let first = sheet(plain, in: fixture)
        #expect(first.payeeText.isEmpty)
        #expect(first.refundOfText == "Running shoes · 17 Oct")
        #expect(first.footnote == "A refund keeps the expense’s category and uses the same currency.")
        #expect(first.caption == "Refund of Running shoes · 17 Oct 2026 · ₹1,000.00")
        let second = sheet(orphaned, in: fixture)
        #expect(second.payeeText.isEmpty)
        #expect(second.refundOfText == "Expense · 17 Oct")
    }

    @Test("D235, P31.5: the payee is editable text; emptied, the refund saves with none")
    func clearPayee() throws {
        let fixture = try F()
        let trailhead = try fixture.payee("Trailhead Sports")
        let expense = try fixture.expense(1_000, on: Self.expenseDate, payee: trailhead)
        let model = sheet(expense, in: fixture)
        model.payeeText = ""
        let change = try #require(model.save())
        let id = try #require(change.transactionIDs.first)
        let refund = try #require(try stored(id, in: fixture))
        #expect(refund.payeeID == nil && refund.details == nil)
        #expect(refund.refundOfID == expense.id && refund.amount == 1_000)
    }

    @Test("D235: the prefilled payee saves as that payee, and an edited one as the payee typed")
    func editedPayee() throws {
        let fixture = try F()
        let trailhead = try fixture.payee("Trailhead Sports")
        let expense = try fixture.expense(1_000, on: Self.expenseDate, payee: trailhead)
        let first = sheet(expense, in: fixture)
        first.amountText = "100"
        let kept = try #require(first.save()?.transactionIDs.first)
        #expect(try stored(kept, in: fixture)?.payeeID == trailhead.id)
        let second = sheet(expense, in: fixture)
        second.amountText = "100"
        second.payeeText = "Trailhead Outlet"
        let edited = try #require(second.save()?.transactionIDs.first)
        let outlet = try #require(try fixture.repository.payees().first { $0.name == "Trailhead Outlet" })
        #expect(try stored(edited, in: fixture)?.payeeID == outlet.id)
    }

    @Test("S15, S16, S49: over refundable, another currency and a date before the expense, in the form's order")
    func errors() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: Self.expenseDate)
        try fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        let model = sheet(expense, in: fixture)
        #expect(model.accountOptions.map(\.label).contains("Travel Card (USD)"))
        #expect(model.accountOptions.map(\.label).contains("Grocery Cash"))
        model.amountText = "701"
        model.accountID = fixture.travelCard.id
        model.pickerDate = F.date(2026, 10, 16, zone: F.kolkata)
        #expect(
            model.messages == [
                "Only ₹700.00 is refundable.",
                "Refund currency must match the expense.",
                "Refund date can’t be before the original expense (17 Oct 2026).",
            ]
        )
        #expect(!model.canSave)
        #expect(model.save() == nil)
        model.amountText = "700"
        model.accountID = fixture.groceryCash.id
        model.pickerDate = Self.expenseDate
        #expect(model.messages.isEmpty)
        #expect(model.canSave)
    }

    @Test("S16: a fully refunded expense shows ₹0.00 refundable and Save stays disabled")
    func fullyRefunded() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: Self.expenseDate)
        try fixture.refund(1_000, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        let model = sheet(expense, in: fixture)
        #expect(model.refundableText == "₹0.00 of ₹1,000.00")
        #expect(model.messages.isEmpty)
        #expect(!model.canSave)
    }

    @Test("S35: a hidden expense account is preselected, and no other hidden account is listed")
    func hiddenAccounts() throws {
        let fixture = try F()
        var holiday = fixture.holidayFund
        holiday.isHidden = true
        try fixture.repository.saveAccount(holiday)
        var hiddenOther = fixture.householdCard
        hiddenOther.isHidden = true
        try fixture.repository.saveAccount(hiddenOther)
        let expense = try fixture.expense(1_000, on: Self.expenseDate, in: holiday)
        let model = sheet(expense, in: fixture)
        #expect(model.accountID == holiday.id)
        let labels = model.accountOptions.map(\.label)
        #expect(labels.contains("Holiday Fund"))
        #expect(!labels.contains("Household Card"))
    }

    @Test("A save is one Undo step that removes only the refund")
    func undo() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: Self.expenseDate)
        let model = sheet(expense, in: fixture)
        let change = try #require(model.save())
        let id = try #require(change.transactionIDs.first)
        #expect(change == .added([id]))
        let window = TestWindow(fixture.useCases)
        window.history.record(change)
        #expect(window.history.undoTitle == "New Transaction in Everyday Savings")
        window.history.undo()
        #expect(try stored(id, in: fixture) == nil)
        #expect(try stored(expense.id, in: fixture) == expense)
    }

    @Test("Live data: a refund from another window lowers what's refundable and keeps what was typed")
    func reload() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: Self.expenseDate)
        let model = sheet(expense, in: fixture)
        model.amountText = "600"
        try fixture.refund(500, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        model.reload()
        #expect(model.amountText == "600")
        #expect(model.refundableText == "₹500.00 of ₹1,000.00")
        #expect(model.messages == ["Only ₹500.00 is refundable."])
        #expect(!model.canSave)
    }

    @Test("Live data: a payee deleted in another window keeps the typed text; a deleted expense can’t save")
    func deletedElsewhere() throws {
        let fixture = try F()
        let trailhead = try fixture.payee("Trailhead Sports")
        let expense = try fixture.expense(1_000, on: Self.expenseDate, payee: trailhead)
        let model = sheet(expense, in: fixture)
        try fixture.repository.deletePayee(id: trailhead.id)
        model.reload()
        #expect(model.payeeText == "Trailhead Sports")
        try fixture.repository.deleteTransaction(id: expense.id)
        model.reload()
        #expect(!model.canSave)
        #expect(model.errorMessage == "This transaction no longer exists.")
        #expect(model.save() == nil)
    }

    @Test("P33: a payee deleted while the sheet is open is saved again by its name, and one Undo removes both")
    func payeeRecreated() throws {
        let fixture = try F()
        let trailhead = try fixture.payee("Trailhead Sports")
        let expense = try fixture.expense(1_000, on: Self.expenseDate, payee: trailhead)
        let model = sheet(expense, in: fixture)
        try fixture.repository.deletePayee(id: trailhead.id)
        model.reload()
        let expenseBefore = try stored(expense.id, in: fixture)
        let change = try #require(model.save())
        // P34: a save that works shows nothing, and the expense is left as it was.
        #expect(model.errorMessage == nil)
        #expect(try stored(expense.id, in: fixture) == expenseBefore)
        let id = try #require(change.transactionIDs.first)
        let payee = try #require(try fixture.repository.payees().first { $0.name == "Trailhead Sports" })
        #expect(payee.id != trailhead.id)
        #expect(try stored(id, in: fixture)?.payeeID == payee.id)
        let window = TestWindow(fixture.useCases)
        window.history.record(change)
        window.history.undo()
        #expect(try stored(id, in: fixture) == nil)
        #expect(try fixture.repository.payees().contains { $0.id == payee.id } == false)
        #expect(try stored(expense.id, in: fixture) == expenseBefore)
        window.history.redo()
        #expect(try stored(id, in: fixture)?.payeeID == payee.id)
        #expect(try fixture.repository.payees().contains { $0.id == payee.id })
        #expect(try stored(expense.id, in: fixture) == expenseBefore)
    }

    @Test("A refund the domain blocks at save time says why and writes nothing")
    func blockedAtSave() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: Self.expenseDate)
        let model = sheet(expense, in: fixture)
        // Recorded in another window after the last check, so the form still allows Save.
        try fixture.refund(800, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        let before = try fixture.repository.transactions()
        #expect(model.save() == nil)
        #expect(model.errorMessage == "Only ₹200.00 is refundable.")
        #expect(try fixture.repository.transactions() == before)
    }

    @Test("S19, S44: Refund and ⌘R are offered on one expense row, never on income, a transfer, a refund or two rows")
    func refundTarget() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: Self.expenseDate)
        let other = try fixture.expense(200, on: Self.expenseDate)
        let refund = try fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        let transfer = try fixture.transfer(100, from: fixture.savings, to: fixture.groceryCash)
        let history = AccountHistoryViewModel(
            useCases: fixture.useCases,
            accountID: fixture.savings.id,
            locale: Locale(identifier: "en_IN"),
            timeZone: TimeZone(identifier: F.kolkata)!,
            now: { F.now },
        )
        history.load()
        #expect(history.refundTarget([expense.id]) == expense.id)
        #expect(history.refundTarget([refund.id]) == nil)
        #expect(history.refundTarget([transfer.id]) == nil)
        #expect(history.refundTarget([expense.id, other.id]) == nil)
        #expect(history.refundTarget([]) == nil)
    }

    /// Stores `expense` split Groceries ₹700.00 / Household ₹300.00, as a saved split is kept on Schema V1.
    private func storeSplit(_ expense: Transaction, in fixture: F) throws {
        let groceries = TransactionCategory(name: "Groceries", kind: .expense)
        let household = TransactionCategory(name: "Household", kind: .expense)
        try fixture.repository.saveCategory(groceries)
        try fixture.repository.saveCategory(household)
        var snapshot = try fixture.repository.ledgerSnapshot()
        snapshot.splits += [
            TransactionSplit(transactionID: expense.id, categoryID: groceries.id, amount: 700, sortOrder: 0),
            TransactionSplit(transactionID: expense.id, categoryID: household.id, amount: 300, sortOrder: 1),
        ]
        for index in snapshot.transactions.indices where snapshot.transactions[index].id == expense.id {
            snapshot.transactions[index].categoryID = nil
        }
        try fixture.repository.replaceLedger(with: snapshot)
    }

    @Test("D35.6, D224.3: a split expense isn't offered Refund or ⌘R on Schema V1; an unsplit one still is")
    func splitNotRefundable() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: Self.expenseDate)
        let plain = try fixture.expense(200, on: Self.expenseDate)
        try storeSplit(expense, in: fixture)
        let history = AccountHistoryViewModel(
            useCases: fixture.useCases,
            accountID: fixture.savings.id,
            locale: Locale(identifier: "en_IN"),
            timeZone: TimeZone(identifier: F.kolkata)!,
            now: { F.now },
        )
        history.load()
        #expect(!history.refundableIDs.contains(expense.id))
        #expect(history.refundTarget([expense.id]) == nil)
        #expect(history.refundTarget([plain.id]) == plain.id)
    }

    @Test("D224.3: a sheet for a split expense has nothing to refund, and one open when the split is saved can't save")
    func splitSheetFailsSafe() throws {
        let fixture = try F()
        let split = try fixture.expense(1_000, on: Self.expenseDate)
        let open = sheet(split, in: fixture)
        #expect(open.canSave)
        try storeSplit(split, in: fixture)
        // Opened from a stale menu: no expense, so the view opens no sheet.
        let late = sheet(split, in: fixture)
        #expect(!late.isAvailable)
        #expect(!late.canSave)
        let before = try fixture.repository.transactions()
        #expect(late.save() == nil)
        // Already open in another window when the split was saved.
        open.reload()
        #expect(!open.isAvailable)
        #expect(!open.canSave)
        #expect(open.save() == nil)
        #expect(try fixture.repository.transactions() == before)
    }

    @Test("P43, D251: an open sheet whose expense is split says so, and is usable again once the split is removed")
    func splitWhileOpen() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: Self.expenseDate)
        let model = sheet(expense, in: fixture)
        model.amountText = "250"
        try storeSplit(expense, in: fixture)
        let before = try fixture.repository.transactions()
        model.reload()
        #expect(model.errorMessage == "This expense is now split, so it can’t be refunded.")
        #expect(!model.canSave)
        #expect(model.save() == nil)
        #expect(try fixture.repository.transactions() == before)
        // OK keeps the sheet open, with what was typed (D251.2).
        model.errorMessage = nil
        #expect(model.amountText == "250")
        // The split is removed in the other window: Refund works again (D251.3).
        var snapshot = try fixture.repository.ledgerSnapshot()
        snapshot.splits.removeAll { $0.transactionID == expense.id }
        for index in snapshot.transactions.indices where snapshot.transactions[index].id == expense.id {
            snapshot.transactions[index].categoryID = fixture.shopping.id
        }
        try fixture.repository.replaceLedger(with: snapshot)
        model.reload()
        #expect(model.errorMessage == nil)
        #expect(model.canSave)
    }

    @Test("D251.4: an open sheet whose expense is deleted keeps “This transaction no longer exists.”")
    func deletedWhileOpen() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: Self.expenseDate)
        let model = sheet(expense, in: fixture)
        try fixture.repository.deleteTransaction(id: expense.id)
        let before = try fixture.repository.transactions()
        model.reload()
        #expect(model.errorMessage == "This transaction no longer exists.")
        #expect(!model.canSave)
        #expect(model.save() == nil)
        #expect(try fixture.repository.transactions() == before)
    }

    @Test(
        "NB1, D251: an open sheet keeps the expense, amounts, account and currency it last read once the expense is split or deleted"
    )
    func keepsLastReadWhenUnavailable() throws {
        let fixture = try F()
        let trailhead = try fixture.payee("Trailhead Sports")
        let expense = try fixture.expense(1_000, on: Self.expenseDate, payee: trailhead)
        try fixture.refund(300, of: expense, on: F.date(2026, 10, 18, zone: F.kolkata))
        for change in ["split", "deleted"] {
            let model = sheet(expense, in: fixture)
            if change == "split" {
                var snapshot = try fixture.repository.ledgerSnapshot()
                let lines = [
                    TransactionSplit(
                        transactionID: expense.id,
                        categoryID: fixture.shopping.id,
                        amount: 700,
                        sortOrder: 0,
                    ),
                    TransactionSplit(transactionID: expense.id, categoryID: nil, amount: 300, sortOrder: 1),
                ]
                snapshot.splits += lines
                try fixture.repository.replaceLedger(with: snapshot)
                model.reload()
                var restored = try fixture.repository.ledgerSnapshot()
                restored.splits.removeAll { $0.transactionID == expense.id }
                try fixture.repository.replaceLedger(with: restored)
            } else {
                try fixture.repository.deleteTransaction(id: expense.id)
                model.reload()
            }
            #expect(!model.isAvailable, "\(change)")
            #expect(!model.canSave, "\(change)")
            #expect(model.refundOfText == "Trailhead Sports · 17 Oct", "\(change)")
            #expect(model.refundableText == "₹700.00 of ₹1,000.00", "\(change)")
            #expect(model.accountID == fixture.savings.id, "\(change)")
            #expect(model.categoryName == "Shopping", "\(change)")
        }
    }
}
