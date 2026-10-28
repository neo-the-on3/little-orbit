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

    /// Every field the Pay sheet edits (D385.1). A field added to the sheet gets a case here in the same PR
    /// (D385.3).
    enum PayField: String, CaseIterable, Sendable {
        case amount, received, paidOn, account, category, changeFuture

        /// The sheet this field is changed on: Rent's, or for Received, Rent Share's between currencies, the only
        /// kind of sheet that shows it.
        @MainActor
        func open(_ scene: ScheduledScene) throws -> (ScheduledListViewModel, ScheduledPayViewModel) {
            if self == .received {
                try scene.addRentShare()
            } else {
                try scene.add(scene.item("Rent", day: 1, month: 10))
            }
            let list = scene.list(scene.feature(), platform: .iOS)
            list.load()
            list.openCustomPay(try #require(list.overdueRows.first))
            return (list, try #require(list.payment))
        }

        /// One switch case per field: changes only that one.
        @MainActor
        func change(_ sheet: ScheduledPayViewModel, _ scene: ScheduledScene) {
            switch self {
            case .amount: sheet.amountText = "26,000"
            case .received: sheet.receivedText = "24"
            case .paidOn: sheet.postedOn = CalendarDay(year: 2026, month: 10, day: 19)
            case .account: sheet.accountID = scene.fund.id
            case .category: sheet.categoryID = nil
            case .changeFuture: sheet.changesFutureOccurrences.toggle()
            }
        }
    }

    @Test(
        "D385: changing only one field of the Pay sheet counts as unsaved edits, so a tapped reminder leaves it open",
        arguments: PayField.allCases,
    )
    func everyFieldCounts(_ field: PayField) throws {
        let scene = try ScheduledScene()
        let (list, sheet) = try field.open(scene)
        let sheets = OpenSheets()
        sheets.opened(UUID(), hasUnsavedEdits: { sheet.hasUnsavedEdits }, close: { list.payment = nil })
        #expect(!sheet.hasUnsavedEdits)
        field.change(sheet, scene)
        #expect(sheet.hasUnsavedEdits, "\(field.rawValue)")
        #expect(sheets.prepareForReminder() == .underneath)
        #expect(list.payment === sheet)
    }
}
