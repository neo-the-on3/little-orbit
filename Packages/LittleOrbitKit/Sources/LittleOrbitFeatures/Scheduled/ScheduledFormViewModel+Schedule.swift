import Foundation
import LittleOrbitDomain

/// The Scheduled form's date pickers and its Next Due Dates preview (D24).
extension ScheduledFormViewModel {
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
}
