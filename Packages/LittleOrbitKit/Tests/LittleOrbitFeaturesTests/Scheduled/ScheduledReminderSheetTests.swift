import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// S33 with UI Designer 6402418696 and Tech Architect 5644974434: a tapped reminder closes untouched sheets first,
/// leaves a sheet with unsaved edits open with the navigation underneath, and opens in the window it's for.
@MainActor
@Suite("Reminder taps over sheets and windows (#26 S33)")
struct ScheduledReminderSheetTests {
    /// A sheet in the registry: whether it has edits, and whether it was closed.
    @MainActor
    private final class Sheet {
        var hasUnsavedEdits: Bool
        private(set) var closed = false
        let id = UUID()

        init(dirty: Bool) {
            hasUnsavedEdits = dirty
        }

        func open(in sheets: OpenSheets, closes order: @escaping (UUID) -> Void = { _ in }) {
            sheets.opened(
                id,
                hasUnsavedEdits: { self.hasUnsavedEdits },
                close: {
                    self.closed = true
                    order(self.id)
                },
            )
        }
    }

    private enum Route: Equatable {
        case account
        case scheduled
        case completed
        case item(UUID)
    }

    @Test("Clean sheets, such as iOS Settings and an untouched form over it, close newest first, then it navigates")
    func cleanSheetsClose() {
        let sheets = OpenSheets()
        let settings = Sheet(dirty: false)
        let form = Sheet(dirty: false)
        var order: [UUID] = []
        settings.open(in: sheets) { order.append($0) }
        form.open(in: sheets) { order.append($0) }
        #expect(sheets.count == 2)
        #expect(sheets.prepareForReminder() == .afterClosing)
        #expect(settings.closed && form.closed)
        #expect(order == [form.id, settings.id])
        #expect(sheets.count == 0)
        let gym = Route.item(UUID())
        #expect(
            ScheduledReminderRouting.path([.account], scheduled: .scheduled, item: gym, sheets: .afterClosing) == [
                .scheduled, gym,
            ]
        )
    }

    @Test("A dirty sheet keeps every sheet open, with no prompt, and the navigation goes underneath")
    func dirtySheetStays() {
        let sheets = OpenSheets()
        let settings = Sheet(dirty: false)
        let editor = Sheet(dirty: true)
        settings.open(in: sheets)
        editor.open(in: sheets)
        #expect(sheets.hasUnsavedEdits)
        #expect(sheets.prepareForReminder() == .underneath)
        #expect(!settings.closed && !editor.closed)
        #expect(sheets.count == 2)
        // The screen showing the sheet stays on the stack: Scheduled and the item go on top of it.
        let gym = Route.item(UUID())
        #expect(
            ScheduledReminderRouting.path([.account], scheduled: .scheduled, item: gym, sheets: .underneath) == [
                .account, .scheduled, gym,
            ]
        )
        // Already on Scheduled, the screens stay and the item goes on top.
        #expect(
            ScheduledReminderRouting.path(
                [.scheduled, .completed],
                scheduled: .scheduled,
                item: gym,
                sheets: .underneath,
            )
                == [.scheduled, .completed, gym]
        )
        // Once its edits are saved or discarded it's clean, and the next tap closes it.
        editor.hasUnsavedEdits = false
        #expect(sheets.prepareForReminder() == .afterClosing)
        #expect(editor.closed && settings.closed)
    }

    @Test("iOS: every tap's item goes on the path, as a row tap pushes it; a deleted item opens the list (D354.2)")
    func everyRouteUsesThePath() {
        let electricity = Route.item(UUID())
        let onPhone: [Route] = [.scheduled, .item(UUID())]
        // A cold launch or clean sheets: Scheduled, then the item, in one go.
        #expect(
            ScheduledReminderRouting.path([], scheduled: .scheduled, item: electricity, sheets: .afterClosing) == [
                .scheduled, electricity,
            ]
        )
        #expect(
            ScheduledReminderRouting.path(onPhone, scheduled: .scheduled, item: electricity, sheets: .afterClosing)
                == [.scheduled, electricity]
        )
        // Deleted: the list on its own, or a Scheduled stack under a dirty sheet left as it is.
        #expect(
            ScheduledReminderRouting.path(onPhone, scheduled: .scheduled, item: nil, sheets: .afterClosing) == [
                .scheduled
            ]
        )
        #expect(
            ScheduledReminderRouting.path([Route.account], scheduled: .scheduled, item: nil, sheets: .underneath) == [
                .account, .scheduled,
            ]
        )
        #expect(
            ScheduledReminderRouting.path(onPhone, scheduled: .scheduled, item: nil, sheets: .underneath) == onPhone
        )
    }

    @Test("B1: a reminder-opened item, then Edit with changes, then a tap for the same item doesn't push it again")
    func reminderOpenedDirtySameItem() {
        let phone = Route.item(UUID())
        // Phone Plan's reminder opens it: the item is on the path, so the next tap can see it.
        let opened = ScheduledReminderRouting.path([], scheduled: .scheduled, item: phone, sheets: .afterClosing)
        #expect(opened == [.scheduled, phone])
        // Edit, a change, then Phone Plan's reminder again: its dirty form stays and nothing is pushed.
        #expect(
            ScheduledReminderRouting.path(opened, scheduled: .scheduled, item: phone, sheets: .underneath) == opened
        )
    }

    @Test("B1: a reminder-opened item with a dirty form, then another item's tap, pushes that item on top once")
    func reminderOpenedDirtyOtherItem() {
        let phone = Route.item(UUID())
        let electricity = Route.item(UUID())
        let opened = ScheduledReminderRouting.path([], scheduled: .scheduled, item: phone, sheets: .afterClosing)
        // Phone Plan's screen and its dirty form stay under Electricity (Tester 6430097769).
        let tapped = ScheduledReminderRouting.path(
            opened,
            scheduled: .scheduled,
            item: electricity,
            sheets: .underneath,
        )
        #expect(tapped == [.scheduled, phone, electricity])
        // The same tap again, before the form is closed, adds no second Electricity.
        #expect(
            ScheduledReminderRouting.path(tapped, scheduled: .scheduled, item: electricity, sheets: .underneath)
                == tapped
        )
    }

    @Test("A closed sheet leaves the registry; with none open it navigates straight away")
    func closedSheetLeaves() {
        let sheets = OpenSheets()
        let form = Sheet(dirty: true)
        form.open(in: sheets)
        sheets.closed(form.id)
        #expect(sheets.count == 0)
        #expect(!sheets.hasUnsavedEdits)
        #expect(sheets.prepareForReminder() == .afterClosing)
        #expect(!form.closed)
    }

    @Test("Scheduled form: clean as it opens, new or edit; dirty once changed; clean again when put back")
    func scheduledFormEdits() throws {
        let scene = try ScheduledScene()
        let rent = scene.item("Rent", day: 1)
        try scene.add(rent)
        let list = scene.list(scene.feature(), platform: .iOS)
        list.load()
        list.openNew()
        let new = try #require(list.form)
        #expect(!new.hasUnsavedEdits)
        new.amountText = "1200"
        #expect(new.hasUnsavedEdits)
        list.openEditor(rent.id)
        let edit = try #require(list.form)
        #expect(edit !== new)
        #expect(!edit.hasUnsavedEdits)
        edit.note = "Landlord"
        #expect(edit.hasUnsavedEdits)
        edit.note = ""
        #expect(!edit.hasUnsavedEdits)
        edit.processesAutomatically.toggle()
        #expect(edit.hasUnsavedEdits)
        edit.processesAutomatically.toggle()
        #expect(!edit.hasUnsavedEdits)
        // A payee typed but not yet created is a change too (#203's payee field).
        edit.payeeText = "Landlord Ltd"
        #expect(edit.hasUnsavedEdits)
    }

    /// Every field the Scheduled form lets the user edit (D385.1). A field added later gets a case here.
    enum FormField: String, CaseIterable, Sendable {
        case type, amount, details, note, account, toAccount, category, payee, payeeText, starts, repeats
        case interval, ends, endDate, automatic, notify

        /// One switch case per field, so the switch's size is the field count.
        @MainActor  // swiftlint:disable:next cyclomatic_complexity
        func change(_ form: ScheduledFormViewModel, _ scene: ScheduledScene) {
            switch self {
            case .type: form.type = .income
            case .amount: form.amountText = "1300"
            case .details: form.details = "Rent, new flat"
            case .note: form.note = "Landlord"
            case .account: form.accountID = scene.fund.id
            case .toAccount: form.transferAccountID = scene.fund.id
            case .category: form.categoryID = nil
            case .payee: form.payeeID = UUID()
            case .payeeText: form.payeeText = "Landlord Ltd"
            case .starts: form.startDay = CalendarDay(year: 2026, month: 8, day: 2)
            case .repeats: form.frequency = .week
            case .interval: form.interval = 2
            case .ends: form.hasEnd.toggle()
            case .endDate: form.endDay = CalendarDay(year: 2027, month: 8, day: 1)
            case .automatic: form.processesAutomatically.toggle()
            case .notify: form.notifiesWhenDue.toggle()
            }
        }
    }

    @Test(
        "D385: changing only one editable field counts as unsaved edits, so a tapped reminder waits",
        arguments: FormField.allCases,
    )
    func everyFieldCounts(_ field: FormField) throws {
        let scene = try ScheduledScene()
        let rent = scene.item("Rent", day: 1)
        try scene.add(rent)
        let list = scene.list(scene.feature(), platform: .iOS)
        list.load()
        list.openEditor(rent.id)
        let form = try #require(list.form)
        let sheets = OpenSheets()
        sheets.opened(UUID(), hasUnsavedEdits: { form.hasUnsavedEdits }, close: { list.form = nil })
        #expect(!form.hasUnsavedEdits)
        field.change(form, scene)
        #expect(form.hasUnsavedEdits, "\(field.rawValue)")
        #expect(sheets.prepareForReminder() == .underneath)
        #expect(list.form === form)
    }

    @Test("A history row's item sheet closes for a tap, unless the form opened over it has unsaved edits")
    func itemSheetWithForm() throws {
        let scene = try ScheduledScene()
        let rent = scene.item("Rent", day: 1)
        try scene.add(rent)
        let list = scene.list(scene.feature(), platform: .iOS)
        list.load()
        let sheets = OpenSheets()
        // As the account history registers its item sheet: it has no edits of its own.
        let item = Sheet(dirty: false)
        item.open(in: sheets)
        list.openEditor(rent.id)
        let form = try #require(list.form)
        sheets.opened(UUID(), hasUnsavedEdits: { form.hasUnsavedEdits }, close: { list.form = nil })
        form.note = "Landlord"
        #expect(sheets.prepareForReminder() == .underneath)
        #expect(!item.closed)
        #expect(list.form != nil)
        form.note = ""
        #expect(sheets.prepareForReminder() == .afterClosing)
        #expect(item.closed)
        #expect(list.form == nil)
    }

    @Test("Tech Architect NB2: a tap for one scene is taken only there; an untargeted tap by any window")
    func tapForItsWindow() {
        let taps = ScheduledReminderTaps()
        taps.windowAppeared("A")
        taps.windowAppeared("B")
        taps.windowAppeared("A")
        #expect(taps.windows == ["A", "B"])
        let item = UUID()
        taps.tapped(itemID: item, window: "B")
        #expect(taps.take(for: "A") == nil)
        #expect(taps.take(for: nil) == nil)
        #expect(taps.take(for: "B")?.itemID == item)
        taps.tapped(itemID: item)
        #expect(taps.take(for: "A")?.itemID == item)
    }

    @Test("A tap waiting for a window that closes goes to the next window that takes it")
    func targetWindowCloses() {
        let taps = ScheduledReminderTaps()
        taps.windowAppeared("A")
        taps.windowAppeared("B")
        taps.tapped(itemID: UUID(), window: "B")
        taps.windowClosed("B")
        #expect(taps.windows == ["A"])
        #expect(taps.take(for: "A") != nil)
    }

    @Test("Mac: the key main window, else the frontmost, else a minimised one; none means open a new one")
    func macWindowChoice() {
        typealias Window = ScheduledReminderRouting.MacWindow
        let back = Window(id: "1", isKey: false, isMiniaturized: false, order: 3)
        let front = Window(id: "2", isKey: false, isMiniaturized: false, order: 1)
        let key = Window(id: "3", isKey: true, isMiniaturized: false, order: 2)
        let minimised = Window(id: "4", isKey: false, isMiniaturized: true, order: nil)
        #expect(ScheduledReminderRouting.macWindow([back, front, key, minimised]) == key)
        #expect(ScheduledReminderRouting.macWindow([back, minimised, front]) == front)
        #expect(ScheduledReminderRouting.macWindow([minimised]) == minimised)
        #expect(ScheduledReminderRouting.macWindow([]) == nil)
    }
}
