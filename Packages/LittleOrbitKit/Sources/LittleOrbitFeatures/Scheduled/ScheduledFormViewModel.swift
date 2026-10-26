import Foundation
import LittleOrbitDomain
import Observation

/// How often the form's item repeats: never, or by one of the units.
public enum ScheduledFrequency: Hashable, Sendable, CaseIterable, Identifiable {
    case never
    case day
    case week
    case month
    case year

    public var id: Self { self }

    var unit: ScheduleUnit? {
        switch self {
        case .never: nil
        case .day: .day
        case .week: .week
        case .month: .month
        case .year: .year
        }
    }

    init(_ rule: ScheduleRepeat) {
        switch rule {
        case .never: self = .never
        case .every(_, .day): self = .day
        case .every(_, .week): self = .week
        case .every(_, .month): self = .month
        case .every(_, .year): self = .year
        }
    }
}

/// One choice in a picker: an account, category or payee, or None.
public struct ScheduledChoice: Identifiable, Hashable, Sendable {
    public let id: UUID?
    public let name: String
}

/// One line of the Next Due Dates preview (#26 design, D24).
public struct ScheduledPreviewRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let date: String
    /// "last day" when a month's last day stands in for a later anchor day.
    public let note: String?
}

/// The New and Edit Scheduled form (#26 design: type, amount, payee, category, account, then Schedule, the next due
/// dates and Process automatically). Editing changes the whole series going forward and never the transactions it
/// already recorded (D114); the stored settled occurrences are kept, whatever this form loaded.
@MainActor
@Observable
public final class ScheduledFormViewModel: Identifiable {
    public let id = UUID()
    public var type: TransactionType {
        didSet { typeChanged() }
    }
    public var amountText: String
    public var details: String
    public var note: String
    public var accountID: UUID? {
        didSet { accountChanged() }
    }
    public var transferAccountID: UUID?
    public var categoryID: UUID?
    public var payeeID: UUID?
    public var startDay: CalendarDay
    public var frequency: ScheduledFrequency
    public var interval: Int
    public var hasEnd: Bool
    public var endDay: CalendarDay
    public var processesAutomatically: Bool
    /// The amount field's error, after a save attempt.
    public private(set) var amountError: String?
    /// An account, transfer or date error, after a save attempt.
    public private(set) var formError: String?
    public var alert: CategoryAlert?

    @ObservationIgnored private let useCases: ScheduledScreenUseCases
    @ObservationIgnored private let listing: ScheduledListing
    @ObservationIgnored private let original: ScheduledItem?
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let timeZoneID: String
    @ObservationIgnored private let today: CalendarDay
    @ObservationIgnored private let saved: () -> Void

    init(
        useCases: ScheduledScreenUseCases,
        listing: ScheduledListing,
        editing item: ScheduledItem?,
        locale: Locale,
        saved: @escaping () -> Void,
    ) {
        self.useCases = useCases
        self.listing = listing
        original = item
        self.locale = locale
        self.saved = saved
        today = useCases.load.today()
        timeZoneID = item?.timeZoneID ?? useCases.load.currentTimeZoneID()
        let accounts = listing.accounts.sorted { $0.sortOrder < $1.sortOrder }
        let currency =
            listing.account(item?.accountID)?.currencyCode ?? accounts.first?.currencyCode ?? CurrencyCode.deviceDefault
        type = item?.type ?? .expense
        amountText = item.map { MoneyFormatter(locale: locale).inputString($0.amount, currencyCode: currency) } ?? ""
        details = item?.details ?? ""
        note = item?.note ?? ""
        accountID = item?.accountID ?? accounts.first?.id
        transferAccountID = item?.transferAccountID
        categoryID = item?.categoryID
        payeeID = item?.payeeID
        startDay = item?.startDay ?? today
        frequency = item.map { ScheduledFrequency($0.repeatRule) } ?? .month
        if case .every(let count, _) = item?.repeatRule {
            interval = count
        } else {
            interval = 1
        }
        hasEnd = item?.endDay != nil
        endDay = item?.endDay ?? item?.startDay ?? today
        processesAutomatically = item?.processesAutomatically ?? false
    }

    public var isNew: Bool { original == nil }
    public var title: String { isNew ? ScheduledText.newTitle : ScheduledText.editTitle }
    public var confirmTitle: String { isNew ? ScheduledText.addButton : CategoryText.save }
    public var cancelTitle: String { CategoryText.cancel }
    public var okayTitle: String { CategoryText.okay }

    // MARK: Labels

    public var amountLabel: String { ScheduledText.amount }
    public var descriptionLabel: String { ScheduledText.descriptionLabel }
    public var noteLabel: String { ScheduledText.note }
    public var payeeLabel: String { ScheduledText.payee }
    public var categoryLabel: String { ScheduledText.category }
    public var accountLabel: String { type == .transfer ? ScheduledText.fromLabel : ScheduledText.account }
    public var toLabel: String { ScheduledText.toLabel }
    public var scheduleHeader: String { ScheduledText.schedule }
    public var startsLabel: String { ScheduledText.starts }
    public var repeatLabel: String { ScheduledText.repeatLabel }
    public var endsLabel: String { ScheduledText.ends }
    public var endsNeverTitle: String { ScheduledText.never }
    public var endsOnDateTitle: String { ScheduledText.onDate }
    public var endDateLabel: String { ScheduledText.endDate }
    public var previewHeader: String { ScheduledText.nextDueDates }
    public var automaticLabel: String { ScheduledText.processAutomatically }
    public var automaticFootnote: String { ScheduledText.automaticFootnote }

    public var typeLabel: String { ScheduledText.typeLabel }
    public func typeName(_ type: TransactionType) -> String { ScheduledText.typeName(type) }

    /// The Repeat picker: Never, Daily, Weekly, Monthly, Yearly (D334.4).
    public func frequencyName(_ frequency: ScheduledFrequency) -> String {
        frequency.unit.map { ScheduledText.every(1, $0) } ?? ScheduledText.never
    }

    /// The stepper row under Repeat, the whole phrase: "Every 2 months", or "Monthly" at 1 (D334.4, D295.1).
    public var intervalText: String {
        frequency.unit.map { ScheduledText.every(interval, $0) } ?? ScheduledText.once
    }

    public var intervalRange: ClosedRange<Int> { ScheduleRepeat.countRange }

    // MARK: Choices

    public var accountChoices: [ScheduledChoice] {
        listing.accounts.sorted { $0.sortOrder < $1.sortOrder }.map { ScheduledChoice(id: $0.id, name: $0.name) }
    }

    /// Accounts in the From account's currency other than it: a scheduled transfer between currencies isn't built
    /// yet.
    public var toChoices: [ScheduledChoice] {
        let currency = listing.account(accountID)?.currencyCode
        return listing.accounts
            .filter { $0.id != accountID && $0.currencyCode == currency }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { ScheduledChoice(id: $0.id, name: $0.name) }
    }

    public var categoryChoices: [ScheduledChoice] {
        let kind: CategoryKind = type == .income ? .income : .expense
        let names = Dictionary(uniqueKeysWithValues: listing.categories.map { ($0.id, $0.name) })
        let categories = listing.categories
            .filter { $0.kind == kind && (!$0.isArchived || $0.id == categoryID) }
            .map { category in
                ScheduledChoice(
                    id: category.id,
                    name: category.parentID.flatMap { names[$0] }.map { ScheduledText.pair($0, category.name) }
                        ?? category.name,
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return [ScheduledChoice(id: nil, name: ScheduledText.none)] + categories
    }

    public var payeeChoices: [ScheduledChoice] {
        let payees = listing.payees
            .map { ScheduledChoice(id: $0.id, name: $0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return [ScheduledChoice(id: nil, name: ScheduledText.none)] + payees
    }

    /// A transfer has neither a category nor a payee, as on a transaction.
    public var showsCategory: Bool { type != .transfer }

    // MARK: Dates

    /// What the date pickers show and set: the day at noon in the device's zone, read back as its day there.
    public var startDate: Date {
        get { date(of: startDay) }
        set { startDay = day(of: newValue) }
    }

    public var endDate: Date {
        get { date(of: endDay) }
        set { endDay = day(of: newValue) }
    }

    private var pickerZone: TimeZone {
        TransactionCalendar.storedTimeZone(useCases.load.currentTimeZoneID())
    }

    private func date(of day: CalendarDay) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pickerZone
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
            ?? Date(
                timeIntervalSince1970: 0
            )
    }

    private func day(of date: Date) -> CalendarDay {
        TransactionCalendar.ownDay(of: date, timeZoneID: pickerZone.identifier)
    }

    // MARK: Preview (D24)

    /// The next five due dates from the start, or from today for an item that's already started, marking a month's
    /// last day standing in for a later anchor day.
    public var preview: [ScheduledPreviewRow] {
        let item = draft(amount: 1)
        let from: CalendarDay
        if !isNew, startDay < today,
            let first = ScheduleCalendar.firstOccurrence(of: item, onOrAfter: today, where: { _ in true })
        {
            from = first
        } else {
            from = startDay
        }
        return ScheduleCalendar.occurrences(of: item, from: from, count: 5)
            .map { day in
                ScheduledPreviewRow(
                    id: "\(day.year)-\(day.month)-\(day.day)",
                    date: ScheduledPresenter.longDate(day, locale: locale),
                    note: ScheduleCalendar.isShortened(day, of: item) ? ScheduledText.lastDayNote : nil,
                )
            }
    }

    /// The D24 footnote, for a monthly or yearly item on the 29th–31st.
    public var previewFootnote: String? {
        guard frequency == .month || frequency == .year, startDay.day > 28 else {
            return nil
        }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .ordinal
        guard let ordinal = formatter.string(from: NSNumber(value: startDay.day)) else {
            return nil
        }
        return ScheduledText.monthEndFootnote(ordinal)
    }

    // MARK: Saving

    private var currencyCode: String {
        listing.account(accountID)?.currencyCode ?? CurrencyCode.deviceDefault
    }

    /// A transfer's To account stays one of the From account's currency.
    private func accountChanged() {
        if type == .transfer, !toChoices.contains(where: { $0.id == transferAccountID }) {
            transferAccountID = toChoices.first?.id
        }
    }

    private func typeChanged() {
        if type == .transfer {
            categoryID = nil
            payeeID = nil
            if transferAccountID == nil || transferAccountID == accountID {
                transferAccountID = toChoices.first?.id
            }
        } else {
            transferAccountID = nil
            if let categoryID, !categoryChoices.contains(where: { $0.id == categoryID }) {
                self.categoryID = nil
            }
        }
    }

    private func draft(amount: Decimal) -> ScheduledItem {
        var item =
            original
            // The store sets a new item's creation date when it's saved.
            ?? ScheduledItem(startDay: startDay, timeZoneID: timeZoneID, createdAt: Date(timeIntervalSince1970: 0))
        item.type = type
        item.amount = amount
        item.accountID = accountID
        item.transferAccountID = type == .transfer ? transferAccountID : nil
        item.categoryID = type == .transfer ? nil : categoryID
        item.payeeID = type == .transfer ? nil : payeeID
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        item.details = trimmed.isEmpty ? nil : trimmed
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        item.note = trimmedNote.isEmpty ? nil : trimmedNote
        item.startDay = startDay
        item.repeatRule = frequency.unit.map { .every(interval, $0) } ?? .never
        item.endDay = hasEnd && frequency != .never ? endDay : nil
        item.processesAutomatically = processesAutomatically
        return item
    }

    /// Checks the form and saves it; `false` keeps the sheet open with the errors shown.
    @discardableResult
    public func save() -> Bool {
        amountError = nil
        formError = nil
        let amount: Decimal
        do {
            amount = try AmountInput.parse(amountText, currencyCode: currencyCode, locale: locale)
        } catch {
            amountError = message(error)
            return false
        }
        guard amount > 0 else {
            amountError = ScheduledText.enterAmount
            return false
        }
        guard accountID != nil else {
            formError = ScheduledText.pickAccount
            return false
        }
        if type == .transfer, transferAccountID == nil || transferAccountID == accountID {
            formError = ScheduledText.pickTwoAccounts
            return false
        }
        let item = draft(amount: amount)
        if let end = item.endDay, end < item.startDay {
            formError = ScheduledText.endBeforeStart
            return false
        }
        do {
            // An edit never saves an item that was deleted while the form was open (#258).
            if isNew {
                try useCases.manage.save(item)
            } else {
                try useCases.manage.update(item)
            }
        } catch LedgerValidationError.scheduleEndsBeforeStart {
            formError = ScheduledText.endBeforeStart
            return false
        } catch {
            alert = ScheduledText.saveFailed
            return false
        }
        saved()
        return true
    }

    /// The account form's messages (D334.12).
    private func message(_ error: AmountInputError) -> String {
        switch error {
        case .tooManyDecimals(let allowed):
            ScheduledText.tooManyDecimals(allowed, currencyCode: currencyCode)
        case .negative, .outOfRange, .notANumber:
            ScheduledText.enterAmountLike(MoneyFormatter(locale: locale).exampleAmount(currencyCode: currencyCode))
        }
    }
}
