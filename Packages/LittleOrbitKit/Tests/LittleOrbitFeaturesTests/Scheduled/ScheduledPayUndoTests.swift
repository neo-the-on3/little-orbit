import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// Pay with a custom date or amount (D24) and Undo for Pay and Skip (D288.3), through a window's history.
@MainActor
@Suite("Scheduled Pay and Skip Undo, and custom pay (#197)")
struct ScheduledPayUndoTests {
    /// A list in a window whose Undo steps the list records.
    private func window(_ scene: ScheduledScene) -> (ScheduledListViewModel, TestWindow) {
        let useCases = TransactionUseCases(
            repository: scene.repository,
            categoryNames: CatalogDefaultCategoryNames(),
            schedule: scene.repository,
        )
        let window = TestWindow(useCases, updates: scene.updates)
        let list = scene.feature().makeList()
        list.recordStep = { [history = window.history] change, name, subject in
            history.record(change, named: name, subject: subject)
        }
        list.load()
        return (list, window)
    }

    @Test("Pay Now is the Undo step Pay Gym; Undo puts the occurrence back and Redo records it again")
    func undoPay() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let (list, window) = window(scene)
        list.payNow(try #require(list.overdueRows.first))
        #expect(scene.recorded.count == 1)
        #expect(window.undoManager.undoActionName == "Pay Gym")
        window.history.undo()
        list.load()
        #expect(scene.recorded.isEmpty)
        #expect(list.overdueRows.count == 1)
        #expect(window.undoManager.redoActionName == "Pay Gym")
        window.history.redo()
        list.load()
        #expect(scene.recorded.count == 1)
        #expect(list.overdueRows.isEmpty)
    }

    @Test("Skip is the Undo step Skip Gym once confirmed; Undo puts the occurrence back")
    func undoSkip() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let (list, window) = window(scene)
        list.confirmSkip(try #require(list.overdueRows.first))
        #expect(!window.undoManager.canUndo)
        list.confirm()
        #expect(window.undoManager.undoActionName == "Skip Gym")
        window.history.undo()
        list.load()
        #expect(list.overdueRows.count == 1)
        #expect(scene.recorded.isEmpty)
    }

    @Test("Undo Pay after the payment was edited elsewhere can't undo and changes nothing (D187.5)")
    func staleUndo() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let (list, window) = window(scene)
        list.payNow(try #require(list.overdueRows.first))
        var paid = try #require(scene.recorded.first)
        paid.amount = 999
        try scene.repository.saveTransaction(paid)
        window.history.undo()
        #expect(window.history.alert?.title == "Can’t Undo Pay Gym")
        #expect(scene.recorded.map(\.amount) == [999])
    }

    @Test("The custom pay sheet reads the design's labels, prefills the amount and keeps the schedule")
    func customPaySheet() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let (list, window) = window(scene)
        list.openCustomPay(try #require(list.overdueRows.first))
        let sheet = try #require(list.payment)
        #expect(sheet.title == "Pay Gym")
        #expect(sheet.confirmTitle == "Record")
        #expect(sheet.paidOnLabel == "Paid on")
        #expect(sheet.changeFutureLabel == "Also change future occurrences")
        #expect(sheet.amountText == "1,200.00")
        #expect(sheet.amountFooter == "Scheduled amount: ₹1,200.00.")
        #expect(
            sheet.changeFutureFooter
                == "Only this occurrence changes. The schedule stays ₹1,200.00 on the 18th. Next due: 18 Nov 2026."
        )
        #expect(sheet.postedOn == CalendarDay(year: 2026, month: 10, day: 20))
        #expect(sheet.accountID == scene.account.id)
        #expect(sheet.categoryChoices.map(\.name) == ["None", "Housing"])
        sheet.changesFutureOccurrences = true
        #expect(
            sheet.changeFutureFooter
                == "Later occurrences use this amount, account and category too. Recorded transactions don’t change. Next due: 18 Nov 2026."
        )
        sheet.changesFutureOccurrences = false
        sheet.amountText = "1350"
        sheet.accountID = scene.fund.id
        sheet.postedOn = CalendarDay(year: 2026, month: 10, day: 19)
        #expect(sheet.record())
        #expect(list.payment == nil)
        let paid = try #require(scene.recorded.first)
        #expect(paid.amount == 1_350)
        #expect(paid.accountID == scene.fund.id)
        #expect(window.undoManager.undoActionName == "Pay Gym")
        #expect(list.upcomingRows.first?.amount == "−₹1,200.00")
        window.history.undo()
        #expect(scene.recorded.isEmpty)
    }

    @Test("Record checks the amount and keeps the sheet open")
    func customPayErrors() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let (list, _) = window(scene)
        list.openCustomPay(try #require(list.overdueRows.first))
        let sheet = try #require(list.payment)
        sheet.amountText = "0"
        #expect(!sheet.record())
        #expect(sheet.amountError == "Enter an amount above zero.")
        #expect(list.payment != nil)
        #expect(scene.recorded.isEmpty)
    }

    @Test(
        "D190: Pay with Custom Date or Amount takes an ellipsis on the Mac, on the item screen and the row menu alike"
    )
    func customPayTitle() throws {
        let scene = try ScheduledScene()
        let mac = ScheduledListViewModel(useCases: scene.useCases, platform: .macOS)
        let phone = ScheduledListViewModel(useCases: scene.useCases, platform: .iOS)
        #expect(mac.payCustomTitle == "Pay with Custom Date or Amount…")
        #expect(phone.payCustomTitle == "Pay with Custom Date or Amount")
    }

    @Test("NB 3: Paid on goes up to today, and a later day picked reads as today")
    func paidOnBound() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let (list, _) = window(scene)
        list.openCustomPay(try #require(list.overdueRows.first))
        let sheet = try #require(list.payment)
        let today = CalendarDay(year: 2026, month: 10, day: 20)
        #expect(TransactionCalendar.ownDay(of: sheet.latestDate, timeZoneID: ScheduledScene.zone) == today)
        sheet.date = sheet.latestDate.addingTimeInterval(3 * 86_400)
        #expect(sheet.postedOn == today)
        sheet.date = sheet.latestDate.addingTimeInterval(-86_400)
        #expect(sheet.postedOn == CalendarDay(year: 2026, month: 10, day: 19))
    }

    @Test("D344: undoing an automatic occurrence's Pay lists it as due without Auto, and catch-up leaves it")
    func automaticUndo() throws {
        let scene = try ScheduledScene()
        // Created on 1 Jul, opened on 20 Oct before any catch-up: Rent's 1 Oct is paid by hand.
        try scene.add(scene.item("Rent", day: 1, automatic: true, month: 10))
        let (list, window) = window(scene)
        list.payNow(try #require(list.overdueRows.first))
        #expect(scene.recorded.count == 1)
        window.history.undo()
        #expect(scene.recorded.isEmpty)
        // Next launch: catch-up records nothing for it, and it waits under Overdue like a manual item.
        let feature = scene.feature()
        feature.catchUp(atLaunch: true)
        #expect(scene.recorded.isEmpty)
        let relaunched = feature.makeList()
        relaunched.load()
        let row = try #require(relaunched.overdueRows.first)
        #expect(row.detail == "Monthly · Everyday Savings")
        #expect(relaunched.overdueHint != nil)
        #expect(feature.plannedItemCounts().overdueOccurrenceCount == 1)
        relaunched.payNow(row)
        #expect(scene.recorded.count == 1)
        #expect(relaunched.overdueRows.isEmpty)
    }
}
