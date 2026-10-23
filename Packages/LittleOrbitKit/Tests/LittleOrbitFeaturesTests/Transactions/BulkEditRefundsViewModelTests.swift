import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// The bulk sheet with refunds and dates (#34; D222.4, D222.5, D223, D226, D227.3, D230.2, D231; P19–P22,
/// P28, P29). macOS only (D225.2); the view model is the same everywhere.
@MainActor
@Suite("Bulk edit sheet: refunds, Date and Account popup (#34)")
struct BulkEditRefundsViewModelTests {
    typealias F = RefundsFeatureFixture  // swiftlint:disable:this type_name

    private func day(_ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: 2026, month: month, day: day)
    }

    @Test("P19: a refund turns Category off with Includes refunds; Payee and Description apply to all rows")
    func includesRefunds() throws {
        let fixture = try F()
        let expenses = try (1...3)
            .map { try fixture.expense(Decimal($0 * 100), on: F.date(2026, 10, $0, zone: F.kolkata)) }
        let refund = try fixture.refund(50, of: expenses[0], on: F.date(2026, 10, 5, zone: F.kolkata))
        let model = fixture.bulkEdit(expenses + [refund])
        #expect(!model.isCategoryEnabled)
        #expect(model.categoryNote == "Includes refunds")
        #expect(model.categoryPopupText == "Includes refunds")
        #expect(
            model.categoryFootnote
                == "Category is unavailable because the selection includes a refund. A refund keeps its expense’s category."
        )
        model.editsPayee = true
        model.payeeText = "Trailhead Sports"
        model.editsDetails = true
        model.updateDetails("Season sale")
        _ = try #require(model.apply())
        let saved = try fixture.repository.transactions()
        #expect(saved.count == 4)
        #expect(saved.allSatisfy { $0.payeeID != nil && $0.details == "Season sale" })
    }

    @Test("P20: an expense moved after its refund saves nothing, says why, and records no step (D222.5)")
    func expenseAfterRefund() throws {
        let fixture = try F()
        let expense = try fixture.expense(1_000, on: F.date(2026, 10, 17, zone: F.kolkata))
        try fixture.refund(300, of: expense, on: F.date(2026, 10, 20, zone: F.kolkata))
        let other = try fixture.expense(200, on: F.date(2026, 10, 18, zone: F.kolkata))
        let before = try fixture.repository.transactions()
        let model = fixture.bulkEdit([expense, other])
        model.editsDate = true
        model.day = day(10, 25)
        #expect(model.apply() == nil)
        #expect(model.errorMessage == "Date can’t be after its refunds (20 Oct 2026).")
        #expect(try fixture.repository.transactions() == before)
    }

    @Test("P28: each row keeps its zone and time, the same on a device in Kolkata or New York; Undo restores")
    func ownZones() throws {
        for deviceZone in [F.kolkata, F.newYork] {
            let fixture = try F()
            let refund = try fixture.refund(
                300,
                of: nil,
                on: F.date(2026, 10, 10, 21, 0, zone: F.london),
                zone: F.london,
            )
            let bakery = try fixture.expense(450, on: F.date(2026, 10, 18, 9, 15, zone: F.kolkata))
            let model = fixture.bulkEdit([refund, bakery], deviceZone: deviceZone)
            model.editsDate = true
            model.day = day(10, 25)
            let change = try #require(model.apply())
            let saved = try fixture.repository.transactions()
            let movedRefund = try #require(saved.first { $0.id == refund.id })
            let movedBakery = try #require(saved.first { $0.id == bakery.id })
            #expect(movedRefund.date == F.date(2026, 10, 25, 21, 0, zone: F.london))
            #expect(movedRefund.timeZoneID == F.london)
            #expect(movedBakery.date == F.date(2026, 10, 25, 9, 15, zone: F.kolkata))
            #expect(movedBakery.timeZoneID == F.kolkata)
            UndoTestSupport.undo(change, useCases: fixture.useCases)
            let restored = try fixture.repository.transactions()
            #expect(restored.first { $0.id == refund.id }?.date == refund.date)
            #expect(restored.first { $0.id == refund.id }?.timeZoneID == F.london)
            #expect(restored.first { $0.id == bakery.id }?.date == bakery.date)
        }
    }

    @Test("D229.4: the picker starts on the first row's own day, in its stored zone")
    func pickerStartsOnOwnDay() throws {
        let fixture = try F()
        // 10 Oct 21:00 in London is already 11 Oct in Kolkata.
        let refund = try fixture.refund(300, of: nil, on: F.date(2026, 10, 10, 21, 0, zone: F.london), zone: F.london)
        let model = fixture.bulkEdit([refund])
        #expect(model.day == day(10, 10))
        #expect(model.pickerTimeZone.identifier == F.london)
    }

    @Test("P29.2, P29.3: only rows that change are written and in the step, whose name counts them (D231.2)")
    func onlyChangedRows() throws {
        let fixture = try F()
        let rows = try [17, 18, 25].map { try fixture.expense(100, on: F.date(2026, 10, $0, 9, 0, zone: F.kolkata)) }
        let model = fixture.bulkEdit(rows)
        #expect(model.title == "Edit 3 Transactions")
        #expect(model.applyTitle == "Apply to 3")
        model.editsDate = true
        model.day = day(10, 25)
        let change = try #require(model.apply())
        #expect(Set(change.transactionIDs) == Set(rows.prefix(2).map(\.id)))
        let untouched = try #require(try fixture.repository.transactions().first { $0.id == rows[2].id })
        #expect(untouched.updatedAt == rows[2].updatedAt)
        let window = TestWindow(fixture.useCases)
        window.history.record(change)
        #expect(window.history.undoTitle == "Edit 2 Transactions in Everyday Savings")
    }

    @Test("P29.5: an Apply that changes nothing closes with no step, and Undo and Redo stay as they were (D231.4)")
    func nothingChanges() throws {
        let fixture = try F()
        let rows = try [24, 25].map { try fixture.expense(100, on: F.date(2026, 10, $0, zone: F.kolkata)) }
        // An earlier edit, undone, so the window has a Redo step to keep.
        let earlier = fixture.bulkEdit([rows[0]])
        earlier.editsDetails = true
        earlier.updateDetails("Weekly order")
        let window = TestWindow(fixture.useCases)
        window.history.record(try #require(earlier.apply()))
        window.history.undo()
        #expect(window.history.canRedo)
        let undoTitle = window.history.undoTitle
        let redoTitle = window.history.redoTitle
        let before = try fixture.repository.transactions()

        let model = fixture.bulkEdit([rows[1]])
        model.editsDate = true
        model.day = day(10, 25)
        #expect(model.canApply)
        #expect(model.apply() == nil)
        #expect(model.errorMessage == nil, "No message: the sheet just closes")
        #expect(try fixture.repository.transactions() == before)
        #expect(window.history.canRedo)
        #expect(window.history.undoTitle == undoTitle)
        #expect(window.history.redoTitle == redoTitle)
    }

    @Test("A new payee isn't created when nothing else would change")
    func noPayeeWithoutChange() throws {
        let fixture = try F()
        let transfer = try fixture.transfer(100, from: fixture.savings, to: fixture.holidayFund)
        let model = fixture.bulkEdit([transfer])
        model.editsPayee = true
        model.payeeText = "Corner Bakery"
        #expect(model.apply() == nil)
        #expect(model.errorMessage == nil)
        #expect(try fixture.repository.payees().isEmpty)
    }

    @Test("P21: the popup disables a selected transfer's To account and accounts in another currency")
    func accountPopup() throws {
        let fixture = try F()
        let rows = try (1...3)
            .map { try fixture.expense(Decimal($0 * 100), on: F.date(2026, 10, $0, zone: F.kolkata)) }
        let transfer = try fixture.transfer(500, from: fixture.savings, to: fixture.holidayFund)
        let model = fixture.bulkEdit(rows + [transfer])
        let reasons = Dictionary(uniqueKeysWithValues: model.accountOptions.map { ($0.name, $0.disabledReason) })
        #expect(reasons["Holiday Fund"] == .some("To account of a selected transfer"))
        #expect(reasons["Travel Card"] == .some("Not in INR"))
        #expect(reasons["Grocery Cash"] == .some(nil))
        #expect(model.isAccountEnabled)
        #expect(
            model.accountFootnote
                == "Transactions can only move to an account in the same currency. A transfer can’t move to its own To account."
        )
        let plain = fixture.bulkEdit(rows)
        #expect(plain.accountFootnote == "Transactions can only move to an account in the same currency.")
        model.editsAccount = true
        model.accountID = fixture.groceryCash.id
        _ = try #require(model.apply())
        #expect(try fixture.repository.transactions().allSatisfy { $0.accountID == fixture.groceryCash.id })
    }

    @Test("P22: a selection in two currencies turns Account off with Mixed currencies")
    func mixedCurrencies() throws {
        let fixture = try F()
        let inr = try fixture.transfer(100, from: fixture.savings, to: fixture.holidayFund)
        let usd = try fixture.expense(20, on: F.date(2026, 10, 2, zone: F.kolkata), in: fixture.travelCard)
        let model = fixture.bulkEdit([inr, usd])
        #expect(!model.isAccountEnabled)
        #expect(model.accountPopupText == "Mixed currencies")
        #expect(
            model.accountFootnote
                == "Transactions can only move to an account in the same currency. A transfer can’t move to its own To account."
        )
    }

    @Test("D227.3: reload follows other windows and keeps the chosen account")
    func reloadKeepsChoice() throws {
        let fixture = try F()
        let rows = try (1...2)
            .map { try fixture.expense(Decimal($0 * 100), on: F.date(2026, 10, $0, zone: F.kolkata)) }
        let model = fixture.bulkEdit(rows)
        model.editsAccount = true
        model.accountID = fixture.groceryCash.id
        try fixture.repository.deleteTransaction(id: rows[1].id)
        model.reload()
        #expect(model.count == 1)
        #expect(model.accountID == fixture.groceryCash.id)
    }
}
