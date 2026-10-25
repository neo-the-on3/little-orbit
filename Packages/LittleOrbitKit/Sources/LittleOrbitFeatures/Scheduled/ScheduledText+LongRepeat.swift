import Foundation
import LittleOrbitDomain

/// The Mac Table's long Repeat forms (D356.2, D357). An interval of 1 has its own key and never reads "Every 1 …";
/// every-N keys are whole-phrase plurals whose forms all show the number. iOS rows and the form's picker keep
/// D334.4's short names.
extension ScheduledText {
    static func weeklyOn(_ weekday: String) -> String {
        FeatureText.format("Weekly on %@", weekday)
    }

    static func everyWeeksOn(_ count: Int, _ weekday: String) -> String {
        FeatureText.pluralFormat(
            "Every %1$lld weeks on %2$@",
            one: "Every %1$lld week on %2$@",
            count: count,
            count,
            weekday,
        )
    }

    static func monthlyOnThe(_ ordinal: String) -> String {
        FeatureText.format("Monthly on the %@", ordinal)
    }

    static var monthlyOnTheLastDay: String {
        FeatureText.string(
            "Monthly on the last day",
            comment: "Mac Scheduled Table Repeat column: every month, on the month’s last day (D357).",
        )
    }

    static func everyMonthsOnThe(_ count: Int, _ ordinal: String) -> String {
        FeatureText.pluralFormat(
            "Every %1$lld months on the %2$@",
            one: "Every %1$lld month on the %2$@",
            count: count,
            count,
            ordinal,
        )
    }

    static func everyMonthsOnTheLastDay(_ count: Int) -> String {
        FeatureText.plural("Every %lld months on the last day", one: "Every %lld month on the last day", count)
    }

    static func yearlyOn(_ dayAndMonth: String) -> String {
        FeatureText.format("Yearly on %@", dayAndMonth)
    }

    static func everyYearsOn(_ count: Int, _ dayAndMonth: String) -> String {
        FeatureText.pluralFormat(
            "Every %1$lld years on %2$@",
            one: "Every %1$lld year on %2$@",
            count: count,
            count,
            dayAndMonth,
        )
    }
}

/// The long Repeat text, from the item's anchor: its start day's weekday, day of the month, or day and month
/// (D24). A monthly item on the 31st is on the last day in every month.
enum ScheduledRepeatText {
    /// The long form for the occurrence on `day`: "Monthly on the 30th, last day" when `day` is a shorter month's
    /// last day (the iOS row's note, D356.2, D357). A rule that already says "last day" doesn't repeat it.
    static func long(_ item: ScheduledItem, on day: CalendarDay?, locale: Locale) -> String {
        let text = long(item, locale: locale)
        guard let day, ScheduleCalendar.isShortened(day, of: item), !saysLastDay(item) else {
            return text
        }
        return ScheduledText.lastDay(text)
    }

    /// A monthly rule on the 31st reads "on the last day" already.
    private static func saysLastDay(_ item: ScheduledItem) -> Bool {
        guard case .every(_, .month) = item.repeatRule else {
            return false
        }
        return item.startDay.day >= 31
    }

    static func long(_ item: ScheduledItem, locale: Locale) -> String {
        guard case .every(let count, let unit) = item.repeatRule else {
            return ScheduledText.once
        }
        let anchor = item.startDay
        switch unit {
        case .day:
            return ScheduledText.every(count, .day)
        case .week:
            let weekday = weekdayName(anchor, locale: locale)
            return count == 1 ? ScheduledText.weeklyOn(weekday) : ScheduledText.everyWeeksOn(count, weekday)
        case .month:
            if anchor.day >= 31 {
                return count == 1
                    ? ScheduledText.monthlyOnTheLastDay : ScheduledText.everyMonthsOnTheLastDay(count)
            }
            let ordinal = ordinal(anchor.day, locale: locale)
            return count == 1 ? ScheduledText.monthlyOnThe(ordinal) : ScheduledText.everyMonthsOnThe(count, ordinal)
        case .year:
            let dayAndMonth = dayAndMonth(anchor, locale: locale)
            return count == 1 ? ScheduledText.yearlyOn(dayAndMonth) : ScheduledText.everyYearsOn(count, dayAndMonth)
        }
    }

    /// "15th", in the locale's ordinal style.
    static func ordinal(_ day: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: day)) ?? "\(day)"
    }

    /// "Saturday".
    static func weekdayName(_ day: CalendarDay, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
        else {
            return ""
        }
        return calendar.weekdaySymbols[calendar.component(.weekday, from: date) - 1]
    }

    /// "15 March", in the locale's order.
    static func dayAndMonth(_ day: CalendarDay, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        // A leap year, so a 29 February anchor reads as itself.
        guard let date = calendar.date(from: DateComponents(year: 2000, month: day.month, day: day.day, hour: 12))
        else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        return formatter.string(from: date)
    }
}
