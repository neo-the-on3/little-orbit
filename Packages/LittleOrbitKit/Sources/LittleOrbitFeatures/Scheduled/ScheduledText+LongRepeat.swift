import Foundation
import LittleOrbitDomain

/// The Mac Table's long Repeat forms (D356.2, D357, D368, D370). An interval of 1 has its own key and never reads "Every 1 …";
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

    /// "Monthly on the 30th or last day": a monthly rule on the 29th or 30th, which falls on a shorter month's
    /// last day (D368). It replaces the iOS row's ", last day" on the Mac.
    static func monthlyOnTheOrLastDay(_ ordinal: String) -> String {
        FeatureText.format("Monthly on the %@ or last day", ordinal)
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

    /// "Every 3 months on the 30th or last day" (D368.1).
    static func everyMonthsOnTheOrLastDay(_ count: Int, _ ordinal: String) -> String {
        FeatureText.pluralFormat(
            "Every %1$lld months on the %2$@ or last day",
            one: "Every %1$lld month on the %2$@ or last day",
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

    /// "Yearly on 29 February or last day of February" (D370).
    static func yearlyOnOrLastDayOfFebruary(_ dayAndMonth: String) -> String {
        FeatureText.format("Yearly on %@ or last day of February", dayAndMonth)
    }

    /// "Every 4 years on 29 February or last day of February" (D370).
    static func everyYearsOnOrLastDayOfFebruary(_ count: Int, _ dayAndMonth: String) -> String {
        FeatureText.pluralFormat(
            "Every %1$lld years on %2$@ or last day of February",
            one: "Every %1$lld year on %2$@ or last day of February",
            count: count,
            count,
            dayAndMonth,
        )
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
/// (D24). A monthly item on the 31st is on the last day in every month, and one on the 29th or 30th on the last day
/// of a shorter month (D368).
enum ScheduledRepeatText {
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
            return monthly(count, on: anchor.day, locale: locale)
        case .year:
            return yearly(count, on: anchor, locale: locale)
        }
    }

    /// "Monthly on the 15th"; on the 29th or 30th, which some months are too short for, "… or last day" (D368,
    /// D368.1).
    private static func monthly(_ count: Int, on day: Int, locale: Locale) -> String {
        let ordinal = ordinal(day, locale: locale)
        switch (count == 1, day >= 29) {
        case (true, true): return ScheduledText.monthlyOnTheOrLastDay(ordinal)
        case (true, false): return ScheduledText.monthlyOnThe(ordinal)
        case (false, true): return ScheduledText.everyMonthsOnTheOrLastDay(count, ordinal)
        case (false, false): return ScheduledText.everyMonthsOnThe(count, ordinal)
        }
    }

    /// "Yearly on 15 March"; on 29 February, "… or last day of February" (D370).
    private static func yearly(_ count: Int, on anchor: CalendarDay, locale: Locale) -> String {
        let dayAndMonth = dayAndMonth(anchor, locale: locale)
        let leapDay = anchor.month == 2 && anchor.day == 29
        switch (count == 1, leapDay) {
        case (true, true): return ScheduledText.yearlyOnOrLastDayOfFebruary(dayAndMonth)
        case (true, false): return ScheduledText.yearlyOn(dayAndMonth)
        case (false, true): return ScheduledText.everyYearsOnOrLastDayOfFebruary(count, dayAndMonth)
        case (false, false): return ScheduledText.everyYearsOn(count, dayAndMonth)
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
