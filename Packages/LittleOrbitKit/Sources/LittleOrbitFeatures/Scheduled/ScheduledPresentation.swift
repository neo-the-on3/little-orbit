import Foundation
import LittleOrbitDomain

/// One row of the Scheduled list (#26 design): an occurrence that's overdue or due today, an active item on its next
/// due day, or a completed item.
public struct ScheduledRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let itemID: UUID
    /// The occurrence the row's Pay Now and Skip act on; `nil` for an upcoming or completed item.
    public let occurrence: CalendarDay?
    public let title: String
    /// "Monthly · Everyday Savings", "Monthly, last day · Auto", "Monthly · From Savings · received $120.00".
    public let detail: String
    public let amount: String
    public let tone: AmountTone
    /// "Overdue · 15 Oct", "Due today" or "1 Nov"; empty on a completed row.
    public let dateText: String
    public let symbolName: String
    /// VoiceOver: name, date and amount (#26 per-platform QA).
    public let spokenLabel: String

    public var canSettle: Bool { occurrence != nil }

    /// This row with Pay Now and Skip acting on `day`.
    func settling(_ day: CalendarDay) -> ScheduledRow {
        ScheduledRow(
            id: id,
            itemID: itemID,
            occurrence: day,
            title: title,
            detail: detail,
            amount: amount,
            tone: tone,
            dateText: dateText,
            symbolName: symbolName,
            spokenLabel: spokenLabel,
        )
    }
}

/// Builds rows from a listing, with dates and money through formatters in the device's locale.
struct ScheduledPresenter {
    let listing: ScheduledListing
    let locale: Locale
    private var money: MoneyFormatter { MoneyFormatter(locale: locale) }

    func name(of item: ScheduledItem) -> String {
        Self.name(
            details: item.details,
            payee: listing.payee(item.payeeID)?.name,
            type: item.type,
            transferTarget: listing.account(item.transferAccountID)?.name,
            category: listing.category(item.categoryID)?.name,
        )
    }

    /// The row's name: the description and payee, else a transfer's To account, else the category. The watch
    /// names its rows with the same rule (#197 item 10).
    static func name(
        details: String?,
        payee: String?,
        type: TransactionType,
        transferTarget: String?,
        category: String?,
    ) -> String {
        let details = details?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        switch (details, payee) {
        case (let details?, let payee?):
            return ScheduledText.pair(details, payee)
        case (let details?, nil):
            return details
        case (nil, let payee?):
            return payee
        case (nil, nil):
            if type == .transfer, let transferTarget {
                return ScheduledText.toAccount(transferTarget)
            }
            return category ?? ScheduledText.scheduledItem
        }
    }

    /// The short name, for confirmation titles: the description, else the row's name.
    func shortName(of item: ScheduledItem) -> String {
        item.details?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? name(of: item)
    }

    func ruleText(_ rule: ScheduleRepeat) -> String {
        switch rule {
        case .never: ScheduledText.once
        case .every(let count, let unit): ScheduledText.every(count, unit)
        }
    }

    func detail(of item: ScheduledItem, on day: CalendarDay?) -> String {
        var rule = ruleText(item.repeatRule)
        if let day, ScheduleCalendar.isShortened(day, of: item) {
            rule = ScheduledText.lastDay(rule)
        }
        var parts = [rule]
        if item.processesAutomatically {
            parts.append(ScheduledText.automatic)
        }
        if let account = listing.account(item.accountID) {
            parts.append(item.type == .transfer ? ScheduledText.fromAccount(account.name) : account.name)
        }
        if let received = receivedText(of: item) {
            parts.append(received)
        }
        return parts.dropFirst().reduce(parts[0]) { ScheduledText.pair($0, $1) }
    }

    /// "received $120.00" in To's currency, for a transfer between currencies (D364, as #23's rows); the row's
    /// amount stays the amount sent.
    func receivedText(of item: ScheduledItem) -> String? {
        guard item.type == .transfer, let received = item.destinationAmount,
            let source = listing.account(item.accountID), let target = listing.account(item.transferAccountID),
            source.currencyCode != target.currencyCode
        else {
            return nil
        }
        return TransferText.received(money.string(received, currencyCode: target.currencyCode))
    }

    func amountText(of item: ScheduledItem) -> (String, AmountTone) {
        let currency = listing.account(item.accountID)?.currencyCode ?? CurrencyCode.deviceDefault
        switch item.type {
        case .expense: return (money.string(-item.amount, currencyCode: currency), .negative)
        case .income: return (money.string(item.amount, currencyCode: currency, showsPlus: true), .positive)
        case .transfer: return (money.string(item.amount, currencyCode: currency), .transfer)
        }
    }

    /// "15 Oct", or "15 Oct 2027" outside this year.
    func dateText(_ day: CalendarDay) -> String {
        Self.date(day, today: listing.board.today, locale: locale)
    }

    static func date(_ day: CalendarDay, today: CalendarDay, locale: Locale) -> String {
        var style = Date.FormatStyle(locale: locale, timeZone: utc).day().month(.abbreviated)
        if day.year != today.year {
            style = style.year()
        }
        return noon(day).formatted(style)
    }

    /// "15 Nov 2026": always with the year, for the Skip message and the Ends value (D334.5, D334.8).
    static func dateWithYear(_ day: CalendarDay, locale: Locale) -> String {
        noon(day).formatted(Date.FormatStyle(locale: locale, timeZone: utc).day().month(.abbreviated).year())
    }

    static func longDate(_ day: CalendarDay, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .long, time: .omitted, locale: locale)
        style.timeZone = utc
        return noon(day).formatted(style)
    }

    static let utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!

    /// A day's noon in UTC: only ever read back as that day in UTC, so the device's zone can't shift it.
    static func noon(_ day: CalendarDay) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
            ?? Date(
                timeIntervalSince1970: 0
            )
    }

    func symbol(of item: ScheduledItem) -> String {
        switch item.type {
        case .expense: "arrow.up.right"
        case .income: "arrow.down.left"
        case .transfer: "arrow.left.arrow.right"
        }
    }

    enum Kind {
        case overdue, dueToday, upcoming, completed
    }

    func row(_ item: ScheduledItem, day: CalendarDay?, kind: Kind) -> ScheduledRow {
        let (amount, tone) = amountText(of: item)
        let date: String =
            switch kind {
            case .overdue: day.map { ScheduledText.overdueOn(dateText($0)) } ?? ""
            case .dueToday: ScheduledText.dueTodayRow
            case .upcoming: day.map(dateText) ?? ""
            case .completed: ""
            }
        let title = name(of: item)
        let spoken = [title, date, amount].filter { !$0.isEmpty }
        let idDay = day.map { "\($0.year)-\($0.month)-\($0.day)" } ?? "item"
        return ScheduledRow(
            id: "\(item.id.uuidString)|\(idDay)",
            itemID: item.id,
            occurrence: kind == .overdue || kind == .dueToday ? day : nil,
            title: title,
            detail: detail(of: item, on: day),
            amount: amount,
            tone: tone,
            dateText: date,
            symbolName: symbol(of: item),
            // "Electricity, Overdue · 15 Aug, −₹1,800.00": parts joined like the account and home rows' labels,
            // with no "and" before the amount (Tester's #198 polish).
            spokenLabel: spoken.joined(separator: ", "),
        )
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

/// Which occurrences the item screen offers Pay and Skip on (D350.2).
public enum ScheduledSettling: Hashable, Sendable {
    /// On the Scheduled screens: each overdue or due-today occurrence (S76).
    case dueOccurrences
    /// From an account history row: that row's occurrence, only when it's the item's next one.
    case historyRow(CalendarDay?)
}
