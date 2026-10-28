import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// D383 and D385 on #20: the custom Pay sheet is in the window's open sheets with its own unsaved-edits check, so
/// a tapped reminder leaves it open while it has changes and closes it first when it has none. Made-up data.
@MainActor
@Suite("The custom Pay sheet and reminder taps (D383, D385)")
struct ScheduledPayUnsavedTests {
    /// The list, its Pay sheet, and the window's open sheets with the Pay sheet in them.
    struct Opened {
        let list: ScheduledListViewModel
        let sheet: ScheduledPayViewModel
        let sheets: OpenSheets
    }

    /// Rent's custom Pay sheet, registered as `ScheduledListView`'s Pay sheet registers it.
    private func paySheet(_ scene: ScheduledScene) throws -> Opened {
        try scene.add(scene.item("Rent", day: 1, month: 10))
        let list = scene.list(scene.feature(), platform: .iOS)
        list.load()
        list.openCustomPay(try #require(list.overdueRows.first))
        let sheet = try #require(list.payment)
        let sheets = OpenSheets()
        sheets.opened(UUID(), hasUnsavedEdits: { sheet.hasUnsavedEdits }, close: { list.payment = nil })
        return Opened(list: list, sheet: sheet, sheets: sheets)
    }

    @Test("D383: Rent's Pay sheet with the amount changed to ₹26,000 stays open with it when a reminder is tapped")
    func changedAmountStays() throws {
        let opened = try paySheet(ScheduledScene())
        let (list, sheet, sheets) = (opened.list, opened.sheet, opened.sheets)
        #expect(!sheet.hasUnsavedEdits)
        sheet.amountText = "26,000"
        #expect(sheet.hasUnsavedEdits)
        #expect(sheets.prepareForReminder() == .underneath)
        #expect(list.payment === sheet)
        #expect(sheet.amountText == "26,000")
    }

    @Test("An untouched Pay sheet closes first, then the reminder opens its item")
    func untouchedCloses() throws {
        let opened = try paySheet(ScheduledScene())
        let (list, sheet, sheets) = (opened.list, opened.sheet, opened.sheets)
        #expect(!sheet.hasUnsavedEdits)
        #expect(sheets.prepareForReminder() == .afterClosing)
        #expect(list.payment == nil)
    }

    @Test("A change put back as it opened is no longer an unsaved edit, so the next tap closes the sheet")
    func changeUndone() throws {
        let opened = try paySheet(ScheduledScene())
        let (list, sheet, sheets) = (opened.list, opened.sheet, opened.sheets)
        let amount = sheet.amountText
        sheet.amountText = "26,000"
        #expect(sheets.prepareForReminder() == .underneath)
        sheet.amountText = amount
        #expect(sheets.prepareForReminder() == .afterClosing)
        #expect(list.payment == nil)
    }
}
