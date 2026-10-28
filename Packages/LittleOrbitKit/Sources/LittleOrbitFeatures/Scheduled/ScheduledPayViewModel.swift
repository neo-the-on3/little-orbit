import Foundation
import LittleOrbitDomain
import Observation

/// Pay with a custom date or amount (#26, D24, #197 design answers): a sheet titled "Pay Electricity" with the
/// amount, prefilled with the scheduled one; "Paid on", today unless changed; the From account; the category; and
/// "Also change future occurrences", off by default (D340). It records this one payment, keyed to the occurrence's own due
/// day, so the next due date follows the original schedule and the anchor day is kept. With the toggle on, the
/// amount, account and category also become the schedule's from now on; its dates never change. It depends only on
/// use-case protocols.
@MainActor
@Observable
public final class ScheduledPayViewModel: Identifiable {
    public let id = UUID()
    public var amountText: String
    public var postedOn: CalendarDay
    /// From, or the account. A From in another currency reformats an amount it can hold exactly in that
    /// currency's decimals, as the Amount field is in From's currency (D415).
    public var accountID: UUID? {
        didSet {
            accountChanged(from: oldValue)
        }
    }
    public var categoryID: UUID?
    public var changesFutureOccurrences = false
    /// A transfer between currencies: the amount To receives, in To's currency, prefilled with the occurrence's (#207,
    /// #202 B1).
    public var receivedText: String {
        didSet {
            if oldValue != receivedText {
                receivedError = nil
            }
        }
    }
    /// The amount field's error, after a Record attempt.
    public private(set) var amountError: String?
    /// The Received field's error, after a Record attempt; cleared by any edit.
    public internal(set) var receivedError: String?
    public var alert: CategoryAlert?
    /// “Discard Changes?” for Cancel, Esc on the Mac or a swipe down with unsaved edits (D411, D300.1).
    public var discard = DiscardConfirmation()
    /// The fields as the sheet opened, for `hasUnsavedEdits`.
    @ObservationIgnored private var openedFields: [AnyHashable] = []

    @ObservationIgnored private let useCases: ScheduledScreenUseCases
    @ObservationIgnored let listing: ScheduledListing
    /// The occurrence as it records: the item with the occurrence's own values in place of its own (D45, D111), so
    /// the prefill, From's choices and Received's currency are the occurrence's (#202 B1).
    @ObservationIgnored let item: ScheduledItem
    /// The item itself, for what the schedule keeps: "The schedule stays ₹1,200.00" and the next due date.
    @ObservationIgnored private let schedule: ScheduledItem
    @ObservationIgnored private let occurrence: CalendarDay
    @ObservationIgnored let locale: Locale
    @ObservationIgnored private let paid: (ScheduledSettlementChange?) -> Void
    public let title: String

    init(
        useCases: ScheduledScreenUseCases,
        listing: ScheduledListing,
        item: ScheduledItem,
        occurrence: CalendarDay,
        locale: Locale,
        paid: @escaping (ScheduledSettlementChange?) -> Void,
    ) {
        self.useCases = useCases
        self.listing = listing
        schedule = item
        let item = item.resolved(for: occurrence)
        self.item = item
        self.occurrence = occurrence
        self.locale = locale
        self.paid = paid
        let presenter = ScheduledPresenter(listing: listing, locale: locale)
        title = ScheduledText.payNamed(presenter.shortName(of: item))
        let currency = listing.account(item.accountID)?.currencyCode ?? CurrencyCode.deviceDefault
        amountText = MoneyFormatter(locale: locale).inputString(item.amount, currencyCode: currency)
        postedOn = useCases.load.today()
        accountID = item.accountID
        categoryID = item.categoryID
        receivedText = ScheduledFormViewModel.receivedText(of: item, listing: listing, locale: locale)
        openedFields = fields
    }

    /// Whether closing the sheet would lose a change: a tapped reminder closes an untouched Pay sheet first and
    /// leaves one with changes open (S33, D383). Every field the user can edit counts (D385.1).
    public var hasUnsavedEdits: Bool {
        fields != openedFields
    }

    /// The fields as they are now; `openedFields` holds them as the sheet opened. Received counts too (#207 on
    /// #201), so an edited amount received asks “Discard Changes?” (D411) like any other field.
    private var fields: [AnyHashable] {
        [amountText, receivedText, postedOn, accountID, categoryID, changesFutureOccurrences]
    }

    /// Cancel, Esc on the Mac or a swipe down on iOS (D411): with unsaved edits, the same fields as `hasUnsavedEdits`,
    /// it asks the Scheduled form's “Discard Changes?” and returns false, so the sheet stays open; otherwise it
    /// returns true, and the sheet closes with nothing paid. Discard Changes closes it with nothing paid too; Keep
    /// Editing leaves every value as it was. A tapped reminder never asks (D383).
    public func requestDismiss(from source: DiscardConfirmation.Source) -> Bool {
        discard.requestDismiss(isDirty: hasUnsavedEdits, from: source)
    }

    public var amountLabel: String { ScheduledText.amount }
    public var paidOnLabel: String { ScheduledText.paidOn }
    public var accountLabel: String { item.type == .transfer ? ScheduledText.fromLabel : ScheduledText.account }
    public var categoryLabel: String { ScheduledText.category }
    public var changeFutureLabel: String { ScheduledText.changeFutureOccurrences }
    public var confirmTitle: String { ScheduledText.record }
    public var cancelTitle: String { CategoryText.cancel }
    public var okayTitle: String { CategoryText.okay }
    /// A transfer has no category, as on a transaction.
    public var showsCategory: Bool { item.type != .transfer }

    /// The Amount field's currency: the chosen From's, or the account's (D415).
    var currencyCode: String {
        listing.account(accountID)?.currencyCode ?? CurrencyCode.deviceDefault
    }

    /// The Amount field's currency code, shown with it.
    public var amountCurrencyCode: String { currencyCode }
    public var amountAccessibilityLabel: String { ScheduledText.amountPaid }

    /// The schedule's own currency: its From's.
    private var scheduleCurrencyCode: String {
        listing.account(item.accountID)?.currencyCode ?? CurrencyCode.deviceDefault
    }

    private var scheduledAmountText: String {
        MoneyFormatter(locale: locale).string(item.amount, currencyCode: scheduleCurrencyCode)
    }

    /// The item's own amount, in its own From's currency: what the schedule keeps while the toggle is off.
    private var seriesAmountText: String {
        let code = listing.account(schedule.accountID)?.currencyCode ?? CurrencyCode.deviceDefault
        return MoneyFormatter(locale: locale).string(schedule.amount, currencyCode: code)
    }

    /// "Scheduled amount: ₹1,850.00.", under the amount; once From is in another currency than the schedule's,
    /// "Scheduled amount: ₹5,000.00, in INR. The amount paid is in USD." (D415).
    public var amountFooter: String {
        currencyCode == scheduleCurrencyCode
            ? ScheduledText.scheduledAmount(scheduledAmountText)
            : ScheduledText.scheduledAmount(scheduledAmountText, in: scheduleCurrencyCode, paidIn: currencyCode)
    }

    /// From moved to another currency: the amount typed is reformatted in the new one when it reads there exactly,
    /// "5,000.00" for USD or "5,000" for JPY; any other text stays as typed, for its error or hint.
    private func accountChanged(from old: UUID?) {
        let oldCode = listing.account(old)?.currencyCode ?? CurrencyCode.deviceDefault
        guard oldCode != currencyCode,
            let amount = try? AmountInput.parse(amountText, currencyCode: oldCode, locale: locale)
        else {
            return
        }
        let formatter = MoneyFormatter(locale: locale)
        let reformatted = formatter.inputString(amount, currencyCode: currencyCode)
        if (try? AmountInput.parse(reformatted, currencyCode: currencyCode, locale: locale)) == amount {
            amountText = reformatted
        }
    }

    /// While the toggle is off: "Only this occurrence changes. The schedule stays ₹1,850.00 on the 15th. Next due:
    /// 15 Nov 2026." While it's on: "Later occurrences use this amount, account and category too. Recorded
    /// transactions don’t change. Next due: 15 Nov 2026." (D341). The anchor sentence names the day only for a
    /// monthly item; the next due date is left out when none follows.
    public var changeFutureFooter: String {
        var sentences: [String]
        if changesFutureOccurrences {
            sentences = [ScheduledText.laterOccurrencesChange]
        } else {
            sentences = [ScheduledText.onlyThisOccurrence]
            if case .every(1, .month) = schedule.repeatRule, let ordinal = ordinal(schedule.startDay.day) {
                sentences.append(ScheduledText.scheduleStays(seriesAmountText, onThe: ordinal))
            } else {
                sentences.append(ScheduledText.scheduleStays(seriesAmountText))
            }
        }
        if let next = nextDue {
            sentences.append(ScheduledText.nextDueSentence(ScheduledPresenter.dateWithYear(next, locale: locale)))
        }
        return CategoryText.sentences(sentences)
    }

    /// The first unsettled occurrence after this one, as it stays on the schedule (D24).
    private var nextDue: CalendarDay? {
        ScheduleCalendar.adding(days: 1, to: occurrence)
            .flatMap { after in
                ScheduleCalendar.firstOccurrence(of: schedule, onOrAfter: after, where: { !schedule.isSettled($0) })
            }
    }

    private func ordinal(_ day: Int) -> String? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: day))
    }

    // MARK: Choices

    /// Every account; for a transfer, every one but To, in any currency, each named with its currency as on the
    /// Scheduled form (#207): one in another currency than To's asks for the amount received too.
    public var accountChoices: [ScheduledChoice] {
        var accounts = listing.accounts
        if item.type == .transfer {
            accounts = accounts.filter { $0.id != item.transferAccountID }
        }
        return accounts.sorted { $0.sortOrder < $1.sortOrder }
            .map { account in
                ScheduledChoice(
                    id: account.id,
                    name: item.type == .transfer
                        ? ScheduledText.pair(account.name, account.currencyCode) : account.name,
                )
            }
    }

    /// The categories of the item's kind, as the Scheduled form lists them, with None first.
    public var categoryChoices: [ScheduledChoice] {
        let kind: CategoryKind = item.type == .income ? .income : .expense
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

    // MARK: Date

    /// What the date picker shows and sets: the day at noon in the device's zone, read back as its day there, as
    /// the Scheduled form's pickers do.
    public var date: Date {
        get { pickerDate(postedOn) }
        set {
            postedOn = min(TransactionCalendar.ownDay(of: newValue, timeZoneID: pickerZone.identifier), today)
        }
    }

    /// The latest "Paid on" day the picker offers: today. A payment is recorded as made, so it's never dated
    /// after today; the transaction entry sheet has no upper bound to follow (Tech Architect NB 3).
    public var latestDate: Date {
        pickerDate(today)
    }

    private var today: CalendarDay {
        useCases.load.today()
    }

    private func pickerDate(_ day: CalendarDay) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pickerZone
        let parts = DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    private var pickerZone: TimeZone {
        TransactionCalendar.storedTimeZone(useCases.load.currentTimeZoneID())
    }

    // MARK: Record

    /// Checks the amount and records the payment; `false` keeps the sheet open with the error or alert shown. An
    /// occurrence another window settled first records nothing more and closes the sheet.
    @discardableResult
    public func record() -> Bool {
        amountError = nil
        let amount: Decimal
        switch readAmount() {
        case .success(let read):
            amount = read
        case .failure(let problem):
            amountError = problem.message
            return false
        }
        var received: Decimal?
        if needsReceivedAmount {
            guard let parsed = parseReceived() else {
                return false
            }
            received = parsed
        }
        let custom = ScheduledCustomPayment(
            amount: amount,
            accountID: accountID,
            categoryID: showsCategory ? categoryID : nil,
            changesFutureOccurrences: changesFutureOccurrences,
            // In To's currency as this sheet read it; the store refuses it if To has moved on (#207 B1).
            receivedAmount: received,
            receivedCurrencyCode: received == nil ? nil : receivedCurrencyCode,
        )
        let change: ScheduledSettlementChange?
        do {
            change = try useCases.manage.pay(itemID: item.id, occurrence: occurrence, on: postedOn, custom: custom)
        } catch LedgerValidationError.receivedCurrencyMismatch {
            // To's currency changed since the sheet read it: nothing was paid, and the sheet stays open (#207 B1).
            alert = ScheduledText.toChangedNothingSaved(listing.account(item.transferAccountID)?.name)
            return false
        } catch {
            alert = ScheduledText.saveFailed
            return false
        }
        paid(change)
        return true
    }

    /// Amount read in From's currency: above zero and in its decimals, or the message saying why not. It sets
    /// nothing, so `canRecord` and `amountHint` can read it as the text changes (D415).
    func readAmount() -> Result<Decimal, ScheduledPayInputProblem> {
        let amount: Decimal
        do {
            amount = try AmountInput.parse(amountText, currencyCode: currencyCode, locale: locale)
        } catch {
            return .failure(ScheduledPayInputProblem(message: message(error)))
        }
        guard amount > 0 else {
            return .failure(ScheduledPayInputProblem(message: ScheduledText.enterAmount))
        }
        return .success(amount)
    }

    /// The Scheduled form's messages (D334.12).
    private func message(_ error: AmountInputError) -> String {
        switch error {
        case .tooManyDecimals(let allowed):
            ScheduledText.tooManyDecimals(allowed, currencyCode: currencyCode)
        case .negative, .outOfRange, .notANumber:
            ScheduledText.enterAmountLike(MoneyFormatter(locale: locale).exampleAmount(currencyCode: currencyCode))
        }
    }
}
