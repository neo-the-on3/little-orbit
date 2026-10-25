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
    public var accountID: UUID?
    public var categoryID: UUID?
    public var changesFutureOccurrences = false
    /// The amount field's error, after a Record attempt.
    public private(set) var amountError: String?
    public var alert: CategoryAlert?

    @ObservationIgnored private let useCases: ScheduledScreenUseCases
    @ObservationIgnored private let listing: ScheduledListing
    @ObservationIgnored private let item: ScheduledItem
    @ObservationIgnored private let occurrence: CalendarDay
    @ObservationIgnored private let locale: Locale
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

    private var currencyCode: String {
        listing.account(accountID)?.currencyCode ?? CurrencyCode.deviceDefault
    }

    private var scheduledAmountText: String {
        let currency = listing.account(item.accountID)?.currencyCode ?? CurrencyCode.deviceDefault
        return MoneyFormatter(locale: locale).string(item.amount, currencyCode: currency)
    }

    /// "Scheduled amount: ₹1,850.00.", under the amount.
    public var amountFooter: String { ScheduledText.scheduledAmount(scheduledAmountText) }

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
            if case .every(1, .month) = item.repeatRule, let ordinal = ordinal(item.startDay.day) {
                sentences.append(ScheduledText.scheduleStays(scheduledAmountText, onThe: ordinal))
            } else {
                sentences.append(ScheduledText.scheduleStays(scheduledAmountText))
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
                ScheduleCalendar.firstOccurrence(of: item, onOrAfter: after, where: { !item.isSettled($0) })
            }
    }

    private func ordinal(_ day: Int) -> String? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: day))
    }

    // MARK: Choices

    /// Every account; for a transfer, those in its To account's currency other than it, as the form allows.
    public var accountChoices: [ScheduledChoice] {
        var accounts = listing.accounts
        if item.type == .transfer {
            let currency = listing.account(item.transferAccountID)?.currencyCode
            accounts = accounts.filter { $0.id != item.transferAccountID && $0.currencyCode == currency }
        }
        return accounts.sorted { $0.sortOrder < $1.sortOrder }.map { ScheduledChoice(id: $0.id, name: $0.name) }
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
        let custom = ScheduledCustomPayment(
            amount: amount,
            accountID: accountID,
            categoryID: showsCategory ? categoryID : nil,
            changesFutureOccurrences: changesFutureOccurrences,
        )
        let change: ScheduledSettlementChange?
        do {
            change = try useCases.manage.pay(itemID: item.id, occurrence: occurrence, on: postedOn, custom: custom)
        } catch {
            alert = ScheduledText.saveFailed
            return false
        }
        paid(change)
        return true
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
