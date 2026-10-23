import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The editor's date in the record's own zone (#131: D229.4, D230.1, D232). Fixture "F131" from Tester's #132 plan,
/// on the #23 sample accounts; names, dates and amounts are made up.
@MainActor
@Suite("Transaction form: the picked day in the record's own zone (#131)")
struct TransactionFormStoredZoneTests {
    typealias F = TransactionFeatureFixture  // swiftlint:disable:this type_name

    nonisolated static let london = "Europe/London"
    nonisolated static let kolkata = "Asia/Kolkata"
    nonisolated static let newYork = "America/New_York"
    nonisolated static let deviceZones = [kolkata, london, newYork]

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, in zone: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    static func expense(_ id: String, _ details: String, on date: Date, zone: String) -> Transaction {
        Transaction(
            id: UUID(uuidString: "13100000-0000-4000-8000-0000000000\(id)")!,
            type: .expense,
            amount: 1_000,
            date: date,
            timeZoneID: zone,
            accountID: F.savingsID,
            details: details,
            createdAt: date,
        )
    }

    static let trailhead = expense("01", "Trailhead Sports", on: date(2026, 10, 10, 1, in: kolkata), zone: kolkata)
    /// R1: ₹300 back on Trailhead Sports, stored as 10 Oct 2026 21:00 London (11 Oct 01:30 in Kolkata).
    static let refund = Transaction(
        id: UUID(uuidString: "13100000-0000-4000-8000-000000000002")!,
        type: .income,
        amount: 300,
        date: date(2026, 10, 10, 21, in: london),
        timeZoneID: london,
        accountID: F.savingsID,
        details: "Trailhead Sports refund",
        refundOfID: trailhead.id,
        isRefund: true,
        createdAt: date(2026, 10, 10, 21, in: london),
    )
    static let bakery = expense("03", "Corner Bakery", on: date(2026, 10, 18, 9, 15, in: kolkata), zone: kolkata)
    static let streamBox = expense("04", "StreamBox", on: date(2026, 3, 20, 1, 30, in: london), zone: london)
    static let lantern = expense("05", "Lantern Books", on: date(2026, 10, 28, 23, in: london), zone: london)
    static let nightBus = expense("06", "Night Bus", on: date(2026, 10, 18, 1, 30, in: london), zone: london)

    struct Setup {
        let repository: InMemoryLedgerRepository
        let useCases: TransactionUseCases
    }

    private func setup() throws -> Setup {
        let repository = try F.repository([Self.trailhead, Self.refund, Self.bakery, Self.streamBox, Self.lantern])
        try repository.saveTransaction(Self.nightBus)
        return Setup(repository: repository, useCases: TransactionUseCases(repository: repository))
    }

    private func form(
        _ setup: Setup,
        _ mode: TransactionFormMode,
        device zone: String,
        now: Date = F.now,
    ) -> TransactionFormViewModel {
        TransactionFormViewModel(
            useCases: setup.useCases,
            mode: mode,
            locale: F.india,
            timeZone: TimeZone(identifier: zone)!,
            now: { now },
        )
    }

    /// What the date picker hands back for a picked day: a moment on that day in the picker's zone, here at
    /// 01:30, a time of day that crosses the day line in the other zones.
    private func pick(_ day: CalendarDay, in model: TransactionFormViewModel) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.pickerTimeZone
        model.pickerDate = calendar.date(
            from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 1, minute: 30)
        )!
    }

    private func stored(_ id: UUID, _ setup: Setup) throws -> Transaction {
        try #require(try setup.repository.transactions().first { $0.id == id })
    }

    private func pickerDay(_ model: TransactionFormViewModel) -> CalendarDay? {
        TransactionCalendar.calendarDay(of: model.pickerDate, timeZoneID: model.pickerTimeZone.identifier)
    }

    @Test("E1 (Z1): on an IST device, R1 moved to 12 Oct is stored as 12 Oct 21:00 London and listed on 12 Oct")
    func pickedDaySavedInRecordZone() throws {
        let setup = try setup()
        let model = form(setup, .edit(Self.refund.id), device: Self.kolkata)
        pick(Self.day(2026, 10, 12), in: model)
        #expect(model.ownDay == Self.day(2026, 10, 12))
        #expect(model.save() != nil)
        let saved = try stored(Self.refund.id, setup)
        #expect(saved.date == Self.date(2026, 10, 12, 21, in: Self.london))
        #expect(saved.timeZoneID == Self.london)
        let listed = TransactionCalendar.groups(try setup.repository.transactions())
        #expect(listed.first { $0.transactions.contains { $0.id == saved.id } }?.day == Self.day(2026, 10, 12))
    }

    @Test("E1 reverse: on a London device, Corner Bakery (Kolkata) moved to 20 Oct keeps 09:15 Kolkata")
    func reverseCrossZone() throws {
        let setup = try setup()
        let model = form(setup, .edit(Self.bakery.id), device: Self.london)
        #expect(pickerDay(model) == Self.day(2026, 10, 18))
        pick(Self.day(2026, 10, 20), in: model)
        #expect(model.save() != nil)
        let saved = try stored(Self.bakery.id, setup)
        #expect(saved.date == Self.date(2026, 10, 20, 9, 15, in: Self.kolkata))
        #expect(saved.timeZoneID == Self.kolkata)
    }

    @Test(
        "E2 (Z2): the label and the picker show R1's own day, 10 Oct, on IST and New York devices",
        arguments: [
            kolkata, newYork,
        ],
    )
    func labelAndPickerShowOwnDay(device: String) throws {
        let model = form(try setup(), .edit(Self.refund.id), device: device)
        #expect(model.ownDay == Self.day(2026, 10, 10))
        #expect(pickerDay(model) == Self.day(2026, 10, 10), "The picker opens on 10 Oct, never 11 Oct")
        #expect(model.dateText == "10 Oct 2026")
        #expect(model.dateSpokenText == "10 October 2026", "VoiceOver: \"Date, 10 October 2026\" on iOS")
        #expect(model.isUnchanged)
    }

    @Test("E3 (Z3): same zone, Corner Bakery moved to 20 Oct is 20 Oct 09:15 Kolkata, as before the fix")
    func sameZone() throws {
        let setup = try setup()
        let model = form(setup, .edit(Self.bakery.id), device: Self.kolkata)
        pick(Self.day(2026, 10, 20), in: model)
        #expect(model.save() != nil)
        let saved = try stored(Self.bakery.id, setup)
        #expect(saved.date == Self.date(2026, 10, 20, 9, 15, in: Self.kolkata))
        #expect(saved.timeZoneID == Self.kolkata)
    }

    @Test("E4 (Z4): R1 moved to 12 Oct gives 12 Oct 21:00 London on every device zone", arguments: deviceZones)
    func independentOfDeviceZone(device: String) throws {
        let setup = try setup()
        let model = form(setup, .edit(Self.refund.id), device: device)
        pick(Self.day(2026, 10, 12), in: model)
        #expect(model.save() != nil)
        let saved = try stored(Self.refund.id, setup)
        #expect(saved.date == Self.date(2026, 10, 12, 21, in: Self.london))
        #expect(saved.timeZoneID == Self.london)
    }

    @Test("E5 (Z5): StreamBox 01:30 London moved to 29 Mar 2026 is 02:00 BST and shows 29 Mar", arguments: deviceZones)
    func daylightSavingGap(device: String) throws {
        let setup = try setup()
        let model = form(setup, .edit(Self.streamBox.id), device: device)
        pick(Self.day(2026, 3, 29), in: model)
        #expect(model.dateText == "29 Mar 2026")
        #expect(model.save() != nil)
        let saved = try stored(Self.streamBox.id, setup)
        #expect(saved.date == Self.date(2026, 3, 29, 2, in: Self.london))
        #expect(saved.timeZoneID == Self.london)
    }

    @Test("E6 (Z6): Undo puts R1 back on 10 Oct 21:00 London, and Redo on 12 Oct 21:00 London")
    func undoAndRedo() throws {
        let setup = try setup()
        let window = TestWindow(setup.useCases)
        let model = form(setup, .edit(Self.refund.id), device: Self.kolkata)
        pick(Self.day(2026, 10, 12), in: model)
        window.history.record(try #require(model.save()))
        #expect(window.history.undoTitle == "Edit Transaction in Everyday Savings")
        window.history.undo()
        var saved = try stored(Self.refund.id, setup)
        #expect(saved.date == Self.date(2026, 10, 10, 21, in: Self.london))
        #expect(saved.timeZoneID == Self.london)
        #expect(window.history.redoTitle == "Edit Transaction in Everyday Savings")
        window.history.redo()
        saved = try stored(Self.refund.id, setup)
        #expect(saved.date == Self.date(2026, 10, 12, 21, in: Self.london))
        #expect(saved.timeZoneID == Self.london)
    }

    @Test("E6 (Z6, D187.5): a date changed since the step makes Undo stale and changes nothing")
    func staleUndoComparesDate() throws {
        let setup = try setup()
        let updates = LedgerUpdates()
        let first = TestWindow(setup.useCases, updates: updates)
        let second = TestWindow(setup.useCases, updates: updates)
        let inFirst = form(setup, .edit(Self.bakery.id), device: Self.kolkata)
        pick(Self.day(2026, 10, 20), in: inFirst)
        first.history.record(try #require(inFirst.save()))
        let inSecond = form(setup, .edit(Self.bakery.id), device: Self.kolkata)
        pick(Self.day(2026, 10, 22), in: inSecond)
        second.history.record(try #require(inSecond.save()))
        first.history.undo()
        #expect(first.history.alert?.title == "Can’t Undo Edit Transaction in Everyday Savings")
        #expect(try stored(Self.bakery.id, setup).date == Self.date(2026, 10, 22, 9, 15, in: Self.kolkata))
    }

    @Test(
        "E7 (Z7, D229.1): the refund's saved own day is the day picked, on every device zone",
        arguments: deviceZones,
    )
    func refundRulesSeePickedDay(device: String) throws {
        let setup = try setup()
        let expenseDay = TransactionTiming.day(of: Self.trailhead)
        #expect(expenseDay == Self.day(2026, 10, 10))
        // R1 on 12 Oct first, as after Z1.
        let first = form(setup, .edit(Self.refund.id), device: device)
        pick(Self.day(2026, 10, 12), in: first)
        #expect(first.save() != nil)

        let model = form(setup, .edit(Self.refund.id), device: device)
        pick(Self.day(2026, 10, 9), in: model)
        #expect(model.ownDay == Self.day(2026, 10, 9))
        #expect(model.ownDay < expenseDay, "Before the expense's own day, which D229's check rejects")
        pick(Self.day(2026, 10, 10), in: model)
        #expect(model.ownDay == expenseDay, "The same own day as the expense, which D229's check allows")
        #expect(model.save() != nil)
        let saved = try stored(Self.refund.id, setup)
        #expect(TransactionTiming.day(of: saved) == expenseDay)
        #expect(saved.date == Self.date(2026, 10, 10, 21, in: Self.london))
        #expect(saved.timeZoneID == Self.london)
    }

    @Test("E8 (Z8): a new expense saved without touching the date is stored at the entry moment in London")
    func newTransactionUnchanged() throws {
        let setup = try setup()
        let entered = Self.date(2026, 10, 23, 14, 5, in: Self.london)
        let model = form(setup, .new(accountID: F.savingsID), device: Self.london, now: entered)
        model.press(.digit(2))
        model.press(.digit(5))
        let change = try #require(model.save())
        let id = try #require(change.transactionIDs.first)
        let saved = try stored(id, setup)
        #expect(saved.date == entered)
        #expect(saved.timeZoneID == Self.london)
    }

    @Test(
        "E10: a new expense with 20 Oct picked keeps its entry time in the device's zone",
        arguments: [
            (london, 14), (newYork, 9),
        ],
    )
    func newTransactionPickedDay(device: String, hour: Int) throws {
        let setup = try setup()
        let entered = Self.date(2026, 10, 23, 14, 5, in: Self.london)
        let model = form(setup, .new(accountID: F.savingsID), device: device, now: entered)
        model.press(.digit(2))
        model.press(.digit(5))
        pick(Self.day(2026, 10, 20), in: model)
        let change = try #require(model.save())
        let id = try #require(change.transactionIDs.first)
        let saved = try stored(id, setup)
        #expect(saved.date == Self.date(2026, 10, 20, hour, 5, in: device))
        #expect(saved.timeZoneID == device)
        #expect(TransactionTiming.day(of: saved) == Self.day(2026, 10, 20))
    }

    @Test("E9: Night Bus 01:30 London moved to 25 Oct is the first 01:30 (BST), and Undo puts back 18 Oct")
    func repeatedHour() throws {
        let setup = try setup()
        let window = TestWindow(setup.useCases)
        for device in Self.deviceZones {
            let model = form(setup, .edit(Self.nightBus.id), device: device)
            pick(Self.day(2026, 10, 25), in: model)
            #expect(model.dateText == "25 Oct 2026", "Shown on 25 Oct with \(device)")
        }
        let model = form(setup, .edit(Self.nightBus.id), device: Self.kolkata)
        pick(Self.day(2026, 10, 25), in: model)
        window.history.record(try #require(model.save()))
        let saved = try stored(Self.nightBus.id, setup)
        #expect(saved.date == Self.date(2026, 10, 25, 0, 30, in: "UTC"))
        #expect(saved.timeZoneID == Self.london)
        window.history.undo()
        #expect(try stored(Self.nightBus.id, setup).date == Self.date(2026, 10, 18, 1, 30, in: Self.london))
    }

    @Test("Picking the day it's already on writes nothing: Save just closes the sheet", arguments: deviceZones)
    func unchangedDayNotWritten(device: String) throws {
        let setup = try setup()
        let before = try setup.repository.transactions()
        let model = form(setup, .edit(Self.refund.id), device: device)
        pick(Self.day(2026, 10, 10), in: model)
        #expect(model.isUnchanged)
        #expect(model.save() == nil)
        #expect(try setup.repository.transactions() == before)
    }

    @Test("Z9: changing only the description keeps R1's stored date, time and zone")
    func otherFieldsKeepDate() throws {
        let setup = try setup()
        let model = form(setup, .edit(Self.refund.id), device: Self.kolkata)
        model.updateDetails("Returned shoes")
        #expect(model.save() != nil)
        let saved = try stored(Self.refund.id, setup)
        #expect(saved.date == Self.refund.date)
        #expect(saved.timeZoneID == Self.london)
        #expect(saved.details == "Returned shoes")
    }

    @Test("Z10 (D35): Lantern Books moved to 1 Nov is 1 Nov 23:00 London, in November", arguments: [kolkata, newYork])
    func periodFollowsPickedDay(device: String) throws {
        let setup = try setup()
        let model = form(setup, .edit(Self.lantern.id), device: device)
        pick(Self.day(2026, 11, 1), in: model)
        #expect(model.save() != nil)
        let saved = try stored(Self.lantern.id, setup)
        #expect(saved.date == Self.date(2026, 11, 1, 23, in: Self.london))
        #expect(TransactionTiming.day(of: saved) == Self.day(2026, 11, 1))
    }

    /// A record whose stored zone ID this device doesn't recognise, as a backup restore can bring back: it goes in
    /// through `replaceLedger`, which skips the save checks, as restore does.
    private func restored(zoneID: String) throws -> (Setup, Transaction) {
        let setup = try setup()
        var record = Self.expense("07", "Harbour Ferry", on: Self.date(2026, 10, 10, 21, in: "UTC"), zone: zoneID)
        record.timeZoneID = zoneID
        var snapshot = try setup.repository.ledgerSnapshot()
        snapshot.transactions.append(record)
        try setup.repository.replaceLedger(with: snapshot)
        return (setup, record)
    }

    @Test(
        "Unknown zone: the label, spoken date and picker show the UTC day the list shows",
        arguments: ["Not/AZone", ""],
    )
    func unknownZoneShowsListDay(zoneID: String) throws {
        let (setup, record) = try restored(zoneID: zoneID)
        let model = form(setup, .edit(record.id), device: Self.kolkata)
        let listed = TransactionTiming.day(of: try stored(record.id, setup))
        #expect(listed == Self.day(2026, 10, 10), "10 Oct 21:00 UTC, though it's 11 Oct in Kolkata")
        #expect(model.ownDay == listed)
        #expect(pickerDay(model) == listed)
        #expect(model.dateText == "10 Oct 2026")
        #expect(model.dateSpokenText == "10 October 2026")
    }

    @Test(
        "Unknown zone: a pick saves the day in UTC without invalidTimeZone, keeps the ID, and Undo restores it",
        arguments: ["Not/AZone", ""],
    )
    func unknownZonePickSaves(zoneID: String) throws {
        let (setup, record) = try restored(zoneID: zoneID)
        let window = TestWindow(setup.useCases)
        let model = form(setup, .edit(record.id), device: Self.kolkata)
        pick(Self.day(2026, 10, 12), in: model)
        #expect(!model.isUnchanged, "The pick lands")
        let change = try #require(model.save())
        #expect(model.errorMessage == nil)
        window.history.record(change)
        let saved = try stored(record.id, setup)
        #expect(saved.date == Self.date(2026, 10, 12, 21, in: "UTC"))
        #expect(saved.timeZoneID == zoneID, "Never rewritten to UTC or the device's zone")
        #expect(TransactionTiming.day(of: saved) == Self.day(2026, 10, 12))
        window.history.undo()
        let undone = try stored(record.id, setup)
        #expect(undone.date == record.date)
        #expect(undone.timeZoneID == zoneID)
    }

    @Test(
        "D230: a date change keeps the stored zone ID, known or not, on any device",
        arguments: [
            (london, kolkata), (london, newYork), ("Not/AZone", kolkata), ("Not/AZone", london),
        ],
    )
    func zoneIDPreserved(zoneID: String, device: String) throws {
        let (setup, record) = try restored(zoneID: zoneID)
        let model = form(setup, .edit(record.id), device: device)
        pick(Self.day(2026, 10, 14), in: model)
        #expect(model.save() != nil)
        let saved = try stored(record.id, setup)
        #expect(saved.timeZoneID == zoneID)
        #expect(TransactionTiming.day(of: saved) == Self.day(2026, 10, 14))
    }
}
