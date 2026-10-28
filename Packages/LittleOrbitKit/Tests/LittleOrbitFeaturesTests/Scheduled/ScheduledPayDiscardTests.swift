import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// D411 on #201: Cancel, Esc on the Mac or a swipe down on an edited custom Pay sheet asks the Scheduled form's
/// “Discard Changes?” (D300.1), using the same fields as the D383/D385 check; an unedited one closes at once, and
/// either way nothing is paid. The view closes the sheet as `ScheduledPayView` does: a `true` from
/// `requestDismiss`, or Discard Changes, sets the list's `payment` to nil. Made-up data.
@MainActor
@Suite("The custom Pay sheet's discard prompt (D411)")
struct ScheduledPayDiscardTests {
    /// Rent's custom Pay sheet, from the list.
    private func paySheet(_ scene: ScheduledScene) throws -> (ScheduledListViewModel, ScheduledPayViewModel) {
        try scene.add(scene.item("Rent", day: 1, month: 10))
        let list = scene.list(scene.feature(), platform: .iOS)
        list.load()
        list.openCustomPay(try #require(list.overdueRows.first))
        return (list, try #require(list.payment))
    }

    @Test(
        "An edited sheet asks “Discard Changes?” from Cancel (Esc on the Mac) and from a swipe, and stays open",
        arguments: ScheduledPayUnsavedTests.PayField.allCases,
    )
    func editedAsks(_ field: ScheduledPayUnsavedTests.PayField) throws {
        let scene = try ScheduledScene()
        let (list, sheet) = try field.open(scene)
        field.change(sheet, scene)
        #expect(!sheet.requestDismiss(from: .cancel), "\(field.rawValue)")
        #expect(sheet.discard.isPresentedFromCancel)
        #expect(!sheet.discard.isPresentedFromSwipe)
        sheet.discard.isPresentedFromCancel = false
        #expect(!sheet.requestDismiss(from: .swipe))
        #expect(sheet.discard.isPresentedFromSwipe)
        #expect(!sheet.discard.isPresentedFromCancel)
        #expect(list.payment === sheet, "Still open")
    }

    @Test("An unedited sheet closes at once, with no prompt and nothing paid")
    func uneditedCloses() throws {
        let scene = try ScheduledScene()
        let (list, sheet) = try paySheet(scene)
        #expect(sheet.requestDismiss(from: .cancel))
        #expect(sheet.requestDismiss(from: .swipe))
        #expect(!sheet.discard.isPresented)
        list.payment = nil
        #expect(scene.recorded.isEmpty)
        #expect(list.overdueRows.count == 1)
    }

    @Test("The prompt is the Scheduled form's: “Discard Changes?”, Discard Changes and Keep Editing, no new copy")
    func sameWording() {
        #expect(DiscardText.title == "Discard Changes?")
        #expect(DiscardText.discard == "Discard Changes")
        #expect(DiscardText.keepEditing == "Keep Editing")
    }

    @Test("Discard Changes closes the sheet with nothing paid: Rent is still overdue, with no transaction")
    func discardPaysNothing() throws {
        let scene = try ScheduledScene()
        let (list, sheet) = try paySheet(scene)
        sheet.amountText = "26,000"
        sheet.changesFutureOccurrences = true
        #expect(!sheet.requestDismiss(from: .cancel))
        // Discard Changes: the dialog closes and the view closes the sheet.
        sheet.discard.isPresentedFromCancel = false
        list.payment = nil
        list.load()
        #expect(scene.recorded.isEmpty)
        #expect(list.overdueRows.count == 1)
        let rent = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        #expect(!rent.isSettled(CalendarDay(year: 2026, month: 10, day: 1)))
        #expect(rent.amount != 26_000, "The schedule didn't change either")
    }

    @Test("Keep Editing goes back to the sheet with every value as it was, and Record then pays it")
    func keepEditingKeepsValues() throws {
        let scene = try ScheduledScene()
        let (list, sheet) = try paySheet(scene)
        sheet.amountText = "26,000"
        sheet.postedOn = CalendarDay(year: 2026, month: 10, day: 19)
        sheet.accountID = scene.fund.id
        sheet.changesFutureOccurrences = true
        #expect(!sheet.requestDismiss(from: .swipe))
        // Keep Editing: only the dialog closes.
        sheet.discard.isPresentedFromSwipe = false
        #expect(!sheet.discard.isPresented)
        #expect(list.payment === sheet)
        #expect(sheet.amountText == "26,000")
        #expect(sheet.postedOn == CalendarDay(year: 2026, month: 10, day: 19))
        #expect(sheet.accountID == scene.fund.id)
        #expect(sheet.changesFutureOccurrences)
        #expect(sheet.hasUnsavedEdits)
        #expect(!sheet.requestDismiss(from: .cancel), "Still asks")
        sheet.discard.isPresentedFromCancel = false
        #expect(sheet.record())
        #expect(scene.recorded.count == 1)
    }
}
