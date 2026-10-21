import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

@MainActor
@Suite("Account history screen")
struct AccountHistoryViewModelTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    private func model(_ repository: InMemoryLedgerRepository, account: UUID = F.savingsID) -> AccountHistoryViewModel {
        let model = AccountHistoryViewModel(
            useCases: TransactionUseCases(repository: repository),
            accountID: account,
            locale: F.india,
            timeZone: F.zone,
            now: { F.now },
        )
        model.load()
        return model
    }

    private func sample() throws -> InMemoryLedgerRepository {
        let cafe = Payee(name: "Cafe Orbit")
        let repository = try F.repository()
        try repository.savePayee(cafe)
        for transaction in [
            F.income(5_000, on: F.date(2026, 10, 19, 9), category: DefaultCategoryID.salary),
            F.transfer(1_000, on: F.date(2026, 10, 19, 18), details: "card payment"),
            F.expense(
                250,
                on: F.date(2026, 10, 20, 9),
                category: DefaultCategoryID.food,
                payee: cafe.id,
                details: "Team lunch",
            ),
            F.expense(750, on: F.date(2026, 11, 3), category: DefaultCategoryID.utilities, details: "Electricity"),
        ] {
            try repository.saveTransaction(transaction)
        }
        return repository
    }

    @Test("Header: current balance leaves Upcoming out; After upcoming includes it (D21)")
    func header() throws {
        let model = model(try sample())
        #expect(model.balanceText == "₹13,750.00")
        #expect(model.afterUpcomingText == "After upcoming: ₹13,000.00")
        #expect(model.upcomingTotalText == "−₹750.00")
        #expect(model.upcoming.map(\.balanceText) == ["Projected ₹13,000.00"])
        #expect(model.upcoming.first?.isUpcoming == true)
    }

    @Test("Days are newest first with Today and net change; rows show the balance after (AC 8)")
    func days() throws {
        let model = model(try sample())
        #expect(model.sections.map(\.title) == ["Today · Tue, 20 Oct", "Yesterday · Mon, 19 Oct"])
        #expect(model.sections.map(\.netChangeText) == ["−₹250.00", "+₹4,000.00"])
        #expect(model.sections[0].rows.map(\.balanceText) == ["Bal ₹13,750.00"])
        #expect(model.sections[1].rows.map(\.balanceText) == ["Bal ₹14,000.00", "Bal ₹15,000.00"])
    }

    @Test("A transfer reads + in the receiving account and keeps the transfer colour (UI Designer, #87 U5)")
    func transferIn() throws {
        let card = model(try sample(), account: F.cardID)
        let transfer = try #require(card.allRows.first { $0.type == .transfer })
        #expect(transfer.compactAmountText == "+₹1,000.00")
        #expect(transfer.amountText == "+₹1,000.00")
        #expect(transfer.amountTone == .transfer)
    }

    @Test("Combined lists keep the unsigned ⇄ amount for transfers (UI Designer, #87 U5)")
    func combinedTransferAmount() {
        let formatter = MoneyFormatter(locale: F.india)
        #expect(
            TransactionRowModel.listAmountText(
                effect: -1_000,
                isTransfer: true,
                currencyCode: "INR",
                formatter: formatter,
                scope: .combined,
            ) == "⇄₹1,000.00"
        )
        #expect(
            TransactionRowModel.listAmountText(
                effect: -1_000,
                isTransfer: true,
                currencyCode: "INR",
                formatter: formatter,
                scope: .account,
            ) == "−₹1,000.00"
        )
        #expect(
            TransactionRowModel.listAmountText(
                effect: -250,
                isTransfer: false,
                currencyCode: "INR",
                formatter: formatter,
                scope: .combined,
            ) == "−₹250.00"
        )
    }

    @Test("Rows: payee title, category · description subtitle, signed amounts, transfer tone")
    func rows() throws {
        let model = model(try sample())
        let lunch = try #require(model.sections.first?.rows.first)
        #expect(lunch.title == "Cafe Orbit")
        #expect(lunch.subtitle == "Food & Dining · Team lunch")
        #expect(lunch.amountText == "−₹250.00")
        #expect(lunch.amountTone == .negative)
        let transfer = model.sections[1].rows[0]
        #expect(transfer.title == "To Rewards Card")
        #expect(transfer.subtitle == "Transfer · card payment")
        #expect(transfer.amountTone == .transfer)
        // In one account's list a transfer is signed, in the transfer colour (UI Designer, #87 U5).
        #expect(transfer.compactAmountText == "−₹1,000.00")
        #expect(transfer.categoryText == "Transfer")
        let salary = model.sections[1].rows[1]
        #expect(salary.amountText == "+₹5,000.00")
        #expect(salary.amountTone == .positive)
        let upcoming = model.upcoming[0]
        #expect(upcoming.title == "Electricity")
        #expect(upcoming.subtitle == "Utilities · 3 Nov")
        #expect(upcoming.accessibilityLabel.contains("Upcoming"))
    }

    @Test("Uncategorised rows say so; the received side of a transfer reads From")
    func uncategorisedAndIncomingTransfer() throws {
        let repository = try F.repository([
            F.expense(100, on: F.date(2026, 10, 18), account: F.cardID),
            F.transfer(1_000, on: F.date(2026, 10, 19)),
        ])
        let model = model(repository, account: F.cardID)
        let rows = model.sections.flatMap(\.rows)
        #expect(rows.map(\.title) == ["From Everyday Savings", "Expense"])
        #expect(rows[1].subtitle == "Uncategorised")
        #expect(rows[0].amountText == "+₹1,000.00")
    }

    @Test("Cross-currency transfer shows what was received (D17)")
    func crossCurrency() throws {
        let repository = try F.repository([F.transfer(1_000, on: F.date(2026, 10, 19), to: F.usdID, received: 12)])
        let row = try #require(model(repository).sections.first?.rows.first)
        #expect(row.subtitle == "Transfer · received $12.00")
        let usd = try #require(model(repository, account: F.usdID).sections.first?.rows.first)
        #expect(usd.amountText == "+$12.00")
        #expect(usd.balanceText == "Bal $112.00")
    }

    @Test("Empty account shows the empty state")
    func empty() throws {
        let model = model(try F.repository())
        #expect(model.isEmpty)
        #expect(model.afterUpcomingText == nil)
        #expect(model.balanceText == "₹10,000.00")
    }

    @Test("Single delete updates at once, offers Undo, and Undo restores every field and attachment (S14, D19)")
    func deleteAndUndo() throws {
        let repository = try sample()
        let model = model(repository)
        let lunch = try #require(model.sections.first?.rows.first)
        let original = try #require(try repository.transactions().first { $0.id == lunch.id })
        try repository.saveAttachment(
            Attachment(
                transactionID: lunch.id,
                fileName: "receipt.jpg",
                contentType: "image/jpeg",
                byteSize: 3,
                data: Data([1, 2, 3]),
            )
        )

        // The iOS toast names the row and its signed amount (D164.2).
        let row = try #require(model.allRows.first { $0.id == lunch.id })
        #expect(model.toastMessage(deleting: [lunch.id]) == "Deleted \(row.title) −₹250.00")
        #expect(model.toastFigure(deleting: [lunch.id]) == "−₹250.00")
        let change = try #require(model.delete(id: lunch.id))
        #expect(model.balanceText == "₹14,000.00")
        #expect(try repository.attachments(for: lunch.id).isEmpty)

        let window = UndoTestSupport.undo(change, useCases: TransactionUseCases(repository: repository))
        model.load()
        #expect(window.history.canRedo)
        #expect(model.balanceText == "₹13,750.00")
        let restored = try #require(try repository.transactions().first { $0.id == lunch.id })
        #expect(restored.amount == original.amount)
        #expect(restored.date == original.date && restored.timeZoneID == original.timeZoneID)
        #expect(restored.categoryID == original.categoryID && restored.payeeID == original.payeeID)
        #expect(restored.details == original.details && restored.note == original.note)
        #expect(try repository.attachments(for: lunch.id).map(\.data) == [Data([1, 2, 3])])
    }

    @Test("Undo recalculates projected balances to match After upcoming (S76)")
    func undoProjected() throws {
        let repository = try sample()
        let model = model(repository)
        let change = try #require(model.delete(id: model.sections[0].rows[0].id))
        #expect(model.upcoming.map(\.balanceText) == ["Projected ₹13,250.00"])
        UndoTestSupport.undo(change, useCases: TransactionUseCases(repository: repository))
        model.load()
        #expect(model.upcoming.map(\.balanceText) == ["Projected ₹13,000.00"])
        #expect(model.afterUpcomingText == "After upcoming: ₹13,000.00")
    }

    @Test("Multi-select delete asks first, removes all, and returns one Undo step (D19, Kiran's decision)")
    func bulkDelete() throws {
        let repository = try sample()
        let model = model(repository)
        let ids = Set(model.sections.flatMap(\.rows).map(\.id))
        model.selection = ids
        #expect(model.selectionSummary == "3 selected")
        #expect(model.requestDelete(ids: ids) == nil)
        let prompt = try #require(model.deletePrompt)
        #expect(prompt.title == "Delete 3 transactions?")
        // D164.5: exactly this, nothing more.
        #expect(prompt.message == "You can undo this.")
        // D164.5: the destructive button says what it does.
        #expect(prompt.confirmTitle == "Delete 3 Transactions")
        #expect(model.toastMessage(deleting: ids) == "3 transactions deleted")
        #expect(model.toastFigure(deleting: ids) == nil)
        #expect(try repository.transactions().count == 4)
        let change = try #require(model.confirmDelete())
        #expect(UndoActionTitle.base(of: change) == "Delete 3 Transactions")
        #expect(try repository.transactions().count == 1)
        #expect(model.deletePrompt == nil)
        #expect(model.selection.isEmpty)
        #expect(model.balanceText == "₹10,000.00")
    }

    @Test("Undoing a bulk delete restores every transaction with its ID; Redo deletes them all again")
    func bulkDeleteUndoRedo() throws {
        let repository = try sample()
        let model = model(repository)
        let before = try repository.transactions()
        let balanceBefore = model.balanceText
        let ids = Set(model.sections.flatMap(\.rows).map(\.id))
        _ = model.requestDelete(ids: ids)
        let change = try #require(model.confirmDelete())

        let window = UndoTestSupport.undo(change, useCases: TransactionUseCases(repository: repository))
        model.load()
        // The bulk includes a transfer, which counts both of its accounts (D166.4).
        window.history.setScreen(.account(F.savingsID))
        #expect(window.history.redoTitle == "Delete 3 Transactions in 2 Accounts")
        let restored = try repository.transactions()
        #expect(Set(restored.map(\.id)) == Set(before.map(\.id)))
        #expect(
            restored.sorted { $0.id.uuidString < $1.id.uuidString }.map(\.amount)
                == before.sorted { $0.id.uuidString < $1.id.uuidString }.map(\.amount)
        )
        #expect(model.balanceText == balanceBefore)

        #expect(window.history.canRedo)
        window.history.redo()
        model.load()
        #expect(Set(try repository.transactions().map(\.id)) == Set(before.map(\.id)).subtracting(ids))
        #expect(model.balanceText == "₹10,000.00")
    }

    @Test("Requesting delete for one row deletes it with Undo")
    func requestSingle() throws {
        let model = model(try sample())
        let id = model.sections[0].rows[0].id
        #expect(model.requestDelete(ids: [id]) != nil)
        #expect(model.deletePrompt == nil)
    }

    @Test("Redo after undo deletes again")
    func redo() throws {
        let repository = try sample()
        let model = model(repository)
        let change = try #require(model.delete(id: model.sections[0].rows[0].id))
        let window = UndoTestSupport.undo(change, useCases: TransactionUseCases(repository: repository))
        #expect(window.history.canRedo)
        window.history.redo()
        model.load()
        #expect(model.balanceText == "₹14,000.00")
    }

    @Test("macOS table text: date, payee, category, account and plain balance")
    func tableText() throws {
        let model = model(try sample())
        let lunch = model.sections[0].rows[0]
        #expect(lunch.dateText == "20 Oct 2026")
        #expect(lunch.accountText == "Everyday Savings")
        #expect(lunch.balanceValueText == "₹13,750.00")
        #expect(model.allRows.count == 4)
    }

    @Test("A transaction entered late on 31 Dec in India stays on 31 Dec in New York (S29)")
    func entryTimeZone() throws {
        let late = Transaction(
            type: .expense,
            amount: 10,
            date: F.date(2025, 12, 31, 23, 59),
            timeZoneID: F.zoneID,
            accountID: F.savingsID,
        )
        let model = AccountHistoryViewModel(
            useCases: TransactionUseCases(repository: try F.repository([late])),
            accountID: F.savingsID,
            locale: F.india,
            timeZone: TimeZone(identifier: "America/New_York")!,
            now: { F.now },
        )
        model.load()
        #expect(model.sections.map(\.title) == ["Wed, 31 Dec 2025"])
    }
}
