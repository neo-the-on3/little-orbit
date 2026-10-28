import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Tech Architect's B1 on #202 (review 5687750600): Pay with Custom Date or Amount opens on the occurrence as it
/// records, with its own values (D45, D111), not the item's. The list row, the item screen and the Mac Table all open
/// the sheet through `openCustomPay`. Made-up data; today is 20 Oct 2026.
@MainActor
@Suite("Custom Pay of an occurrence with its own values (#202 B1)")
struct ScheduledPayOccurrenceValuesTests {
    private let gymKey = CalendarDay(year: 2026, month: 10, day: 18)
    private let shareKey = CalendarDay(year: 2026, month: 10, day: 1)
    private let tokyo = Account(name: "Tokyo Wallet", type: .cash, currencyCode: "JPY", sortOrder: 4)

    /// Saves `change` on the occurrence at `key` with This occurrence only.
    private func editOccurrence(
        _ scene: ScheduledScene,
        _ key: CalendarDay,
        _ change: (inout ScheduledItem) -> Void,
    ) throws {
        let item = try #require(try scene.repository.scheduleLedger().scheduledItems.first)
        var form = item.resolved(for: key)
        form.occurrences = item.occurrences
        change(&form)
        let save = ScheduledOccurrenceSave(occurrence: key, dueDay: key, scope: .thisOccurrence)
        _ = try scene.useCases.manage.update(form, editing: save, payee: nil)
    }

    private func sheet(_ scene: ScheduledScene, platform: ScheduledPlatform) throws -> ScheduledPayViewModel {
        let list = scene.list(scene.feature(), platform: platform)
        list.load()
        list.openCustomPay(try #require(list.overdueRows.first))
        return try #require(list.payment)
    }

    @Test(
        "Gym's 18 Oct with its own ₹1,300: the sheet shows ₹1,300; a date-only change records ₹1,300 once",
        arguments: [ScheduledPlatform.iOS, .macOS],
    )
    func ownAmount(platform: ScheduledPlatform) throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        try editOccurrence(scene, gymKey) { $0.amount = 1_300 }
        let sheet = try sheet(scene, platform: platform)
        let formatter = MoneyFormatter(locale: Locale(identifier: "en_IN"))
        #expect(sheet.amountText == formatter.inputString(1_300, currencyCode: "INR"))
        #expect(sheet.amountFooter == ScheduledText.scheduledAmount(formatter.string(1_300, currencyCode: "INR")))
        #expect(
            sheet.changeFutureFooter.contains(formatter.string(1_200, currencyCode: "INR")),
            "The schedule itself stays ₹1,200",
        )
        sheet.postedOn = CalendarDay(year: 2026, month: 10, day: 19)
        #expect(sheet.record())
        #expect(scene.recorded.map(\.amount) == [1_300])
        withExtendedLifetime(scene) {}
    }

    @Test("Rent Share's 1 Oct with its own Tokyo Wallet and ¥1,801: Received asks in JPY, prefilled, and records")
    func ownToInAnotherCurrency() throws {
        let scene = try ScheduledScene()
        try scene.addRentShare()
        try scene.repository.saveAccount(tokyo)
        try editOccurrence(scene, shareKey) { form in
            form.transferAccountID = tokyo.id
            form.destinationAmount = 1_801
            form.receivedCurrencyCode = "JPY"
        }
        let sheet = try sheet(scene, platform: .iOS)
        #expect(sheet.needsReceivedAmount)
        #expect(sheet.receivedCurrencyCode == "JPY")
        let formatter = MoneyFormatter(locale: Locale(identifier: "en_IN"))
        #expect(sheet.receivedText == formatter.inputString(1_801, currencyCode: "JPY"))
        #expect(!sheet.accountChoices.contains { $0.id == tokyo.id }, "From never lists the occurrence's own To")
        #expect(sheet.canRecord)
        sheet.postedOn = CalendarDay(year: 2026, month: 10, day: 2)
        #expect(sheet.record())
        let paid = try #require(scene.recorded.first)
        #expect(paid.transferAccountID == tokyo.id)
        #expect(paid.destinationAmount == 1_801)
        #expect(scene.recorded.count == 1)
        withExtendedLifetime(scene) {}
    }
}
