import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// Tester's Mac pass at 66697b7 on #202 and Tech Architect's B1, on the screens. Made-up data.
@MainActor
@Suite("Scheduled one-off and deleted-account edits on the screens (#202)")
struct ScheduledOneOffEditViewModelTests {
    private let november = CalendarDay(year: 2026, month: 11, day: 1)

    private func list(_ scene: ScheduledScene) -> ScheduledListViewModel {
        let list = ScheduledListViewModel(
            useCases: scene.useCases,
            locale: Locale(identifier: "en_IN"),
            platform: .macOS,
        )
        list.load()
        return list
    }

    @Test("#202 Tester: Never from the occurrence keeps the row's values, and the one-off form's ₹1,400 takes effect")
    func oneOffFormTakesEffect() throws {
        let scene = try ScheduledScene()
        var phone = scene.item("Phone Plan", day: 1, month: 11)
        phone.accountID = scene.fund.id
        try scene.add(phone)
        let list = list(scene)
        // 1 Nov alone: ₹1,300 on Everyday Savings.
        list.openEditor(phone.id, occurrence: november)
        let form = try #require(list.form)
        form.amountText = "1300"
        form.accountID = scene.account.id
        #expect(form.save() == false)
        #expect(form.save(scope: .thisOccurrence))
        // Repeat set to Never from that occurrence: no question, and the row still reads ₹1,300 on Everyday Savings.
        list.openEditor(phone.id, occurrence: november)
        let never = try #require(list.form)
        never.frequency = .never
        #expect(never.save())
        let once = try #require(list.upcomingRows.first)
        #expect(once.amount.contains("1,300"))
        #expect(once.detail.contains("Everyday Savings"))
        // The one-off form opens on those values and its save changes the row and what Pay Now records.
        list.openEditor(once.itemID, occurrence: once.editOccurrence)
        let oneOff = try #require(list.form)
        #expect(!oneOff.showsDueDate)
        #expect(oneOff.accountID == scene.account.id)
        oneOff.amountText = "1400"
        #expect(oneOff.save())
        let row = try #require(list.upcomingRows.first)
        #expect(row.amount.contains("1,400"))
        scene.now = ScheduledScene.date(november)
        list.load()
        let due = try #require(list.dueTodayRows.first)
        list.payNow(due)
        list.payNow(due)
        #expect(scene.recorded.map(\.amount) == [1_400])
        #expect(scene.recorded.first?.accountID == scene.account.id)
    }

    @Test("#202 B1: delete the account one occurrence uses, then a backup restores and the row shows the item's")
    func deletedAccountBackupRestores() throws {
        let scene = try ScheduledScene()
        let rent = scene.item("Rent", day: 1, month: 11)
        try scene.add(rent)
        let list = list(scene)
        list.openEditor(rent.id, occurrence: november)
        let form = try #require(list.form)
        form.accountID = scene.fund.id
        #expect(form.save() == false)
        #expect(form.save(scope: .thisOccurrence))
        try scene.repository.deleteAccount(id: scene.fund.id)
        list.load()
        let row = try #require(list.upcomingRows.first)
        #expect(row.detail.contains("Everyday Savings"))
        let codec = BackupCodec(hashing: FakeBackupHashing())
        let contents = BackupContents(
            manifest: BackupManifest(
                kind: .automatic,
                createdAt: scene.now,
                nameIndex: 1,
                schemaVersion: "1.0.0",
                accountCount: 1,
                transactionCount: 0,
                attachmentCount: 0,
            ),
            ledger: try scene.repository.ledgerSnapshot(),
        )
        let decoded = try codec.decode(try codec.encode(contents))
        try scene.repository.replaceLedger(with: decoded.ledger)
        list.load()
        #expect(list.upcomingRows.first?.detail.contains("Everyday Savings") == true)
    }
}
