import Foundation

/// The order of day, month and year in a file's dates.
public enum ImportDateOrder: String, CaseIterable, Sendable, Codable {
    /// 20/10/2026 (en_IN, en_GB, de_DE)
    case dayMonthYear
    /// 10/20/2026 (en_US)
    case monthDayYear
    /// 2026-10-20 (ISO 8601, Debit & Credit)
    case yearMonthDay
}

/// What date detection found in a column (#30 PM answer 1, S6–S9).
public struct ImportDateDetection: Equatable, Sendable {
    /// The order to read with: the only one that reads every date, or the region's when several do.
    public var order: ImportDateOrder
    /// Every order that reads every date. More than one means the file is ambiguous and the user can switch.
    public var candidates: [ImportDateOrder]

    public init(order: ImportDateOrder, candidates: [ImportDateOrder]) {
        self.order = order
        self.candidates = candidates
    }

    public var isAmbiguous: Bool {
        candidates.count > 1
    }
}

/// A date and time as written in a file, with no time zone.
public struct ImportWallTime: Equatable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int
    public var hour: Int
    public var minute: Int
    public var second: Int

    public init(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
    }
}

/// Reads dates in a file: three numbers separated by `/`, `-`, `.` or spaces, a compact year-first `20261105`,
/// or a day and year around a month name in English or the device's language (`20 Oct 2026`, `20. Okt. 2026`;
/// #189 I15, D387.6), optionally followed by a time (`10:30`, `10:30:15`, `10:30 PM`) after a space or `T`.
/// Two-digit years are 2000–2099. Dates that don't exist (31/02) aren't read. Parsing never depends on the
/// region; only the default order for an ambiguous file comes from it.
public enum ImportDateParser {
    public static func wallTime(
        _ text: String,
        order: ImportDateOrder,
        months: ImportMonthNames = .device,
    ) -> ImportWallTime? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let (datePart, timePart) = split(trimmed)
        guard let date = calendarDate(datePart, order: order, months: months) else {
            return nil
        }
        guard let time = timePart.map(clockTime) ?? ClockTime(hour: 0, minute: 0, second: 0) else {
            return nil
        }
        return ImportWallTime(
            year: date.year,
            month: date.month,
            day: date.day,
            hour: time.hour,
            minute: time.minute,
            second: time.second,
        )
    }

    /// The order that reads the samples. Blank samples are skipped. When several orders read all of them, the
    /// region's order wins if it's one of them (#30 S6, S8); if none reads them all, the one that reads most.
    public static func detect(
        _ samples: [String],
        locale: Locale,
        months: ImportMonthNames = .device,
    ) -> ImportDateDetection {
        let values = samples.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let preferred = order(for: locale)
        var counts: [ImportDateOrder: Int] = [:]
        for order in ImportDateOrder.allCases {
            counts[order] = values.filter { wallTime($0, order: order, months: months) != nil }.count
        }
        let best = counts.values.max() ?? 0
        guard best > 0 else {
            return ImportDateDetection(order: preferred, candidates: [])
        }
        let ranking = [preferred] + ImportDateOrder.allCases.filter { $0 != preferred }
        let candidates = ranking.filter { counts[$0] == best }
        return ImportDateDetection(order: candidates[0], candidates: candidates)
    }

    /// The region's order: where its numeric short date puts the day, month and year.
    public static func order(for locale: Locale) -> ImportDateOrder {
        let pattern = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale) ?? "M/d/y"
        let positions = ["d", "M", "y"].map { mark in pattern.firstIndex(of: Character(mark)) ?? pattern.endIndex }
        if positions[2] < positions[0] && positions[2] < positions[1] {
            return .yearMonthDay
        }
        return positions[0] < positions[1] ? .dayMonthYear : .monthDayYear
    }

    /// The moment `wallTime` names in `timeZone`. A time that doesn't exist because the clocks jump forward
    /// moves forward by the length of the jump (02:30 → 03:30); a time that happens twice is the first
    /// occurrence (D38.3).
    public static func date(_ wallTime: ImportWallTime, in timeZone: TimeZone) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(
            year: wallTime.year,
            month: wallTime.month,
            day: wallTime.day,
            hour: wallTime.hour,
            minute: wallTime.minute,
            second: wallTime.second,
        )
        let local = utc.date(from: components)!.timeIntervalSince1970
        let before = TimeInterval(timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: local - 86_400)))
        let after = TimeInterval(timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: local + 86_400)))
        let candidates = Set([local - before, local - after]).sorted()
        for instant in candidates {
            let offset = TimeInterval(timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: instant)))
            if instant + offset == local {
                return Date(timeIntervalSince1970: instant)
            }
        }
        // In the gap: read with the offset from before the jump, which lands as far after it as the wall time
        // was after the jump's start.
        return Date(timeIntervalSince1970: local - before)
    }

    // MARK: - Pieces

    private static func split(_ text: String) -> (String, String?) {
        if let tIndex = text.firstIndex(of: "T"), text[text.index(after: tIndex)...].contains(":"),
            text[..<tIndex].allSatisfy({ $0.isASCIIDigit || $0 == "-" })
        {
            return (String(text[..<tIndex]), String(text[text.index(after: tIndex)...]))
        }
        guard let colon = text.firstIndex(of: ":") else {
            return (text, nil)
        }
        // The time starts at the last space before its first colon.
        guard let space = text[..<colon].lastIndex(where: { $0 == " " }) else {
            return (text, nil)
        }
        return (
            text[..<space].trimmingCharacters(in: .whitespaces),
            text[text.index(after: space)...].trimmingCharacters(in: .whitespaces),
        )
    }

    private struct ClockTime {
        var hour: Int
        var minute: Int
        var second: Int
    }

    /// The time without its AM/PM mark and any zone suffix, and the mark. A zone (Z or +05:30) isn't used: rows
    /// are read as wall time in the device zone.
    private static func clockBody(_ text: String) -> (body: String, meridiem: String?) {
        var body = text.uppercased()
        var meridiem: String?
        for mark in ["AM", "PM"] where body.hasSuffix(mark) {
            meridiem = mark
            body = String(body.dropLast(2)).trimmingCharacters(in: .whitespaces)
        }
        if body.hasSuffix("Z") {
            body.removeLast()
        }
        if let plus = body.lastIndex(where: { $0 == "+" || $0 == "-" }) {
            body = String(body[..<plus])
        }
        return (body, meridiem)
    }

    private static func clockTime(_ text: String) -> ClockTime? {
        let (body, meridiem) = clockBody(text)
        let parts = body.split(separator: ":").map(String.init)
        guard (2...3).contains(parts.count) else {
            return nil
        }
        let secondsText = parts.count == 3 ? String(parts[2].prefix { $0 != "." && $0 != "," }) : "0"
        guard let hour = Int(parts[0]), let minute = Int(parts[1]), let second = Int(secondsText),
            parts[0].count <= 2, parts[1].count == 2, (0...59).contains(minute), (0...59).contains(second)
        else {
            return nil
        }
        guard let hour24 = twentyFourHour(hour, meridiem: meridiem) else {
            return nil
        }
        return ClockTime(hour: hour24, minute: minute, second: second)
    }

    private static func twentyFourHour(_ hour: Int, meridiem: String?) -> Int? {
        switch meridiem {
        case "AM":
            (1...12).contains(hour) ? hour % 12 : nil
        case "PM":
            (1...12).contains(hour) ? hour % 12 + 12 : nil
        default:
            (0...23).contains(hour) ? hour : nil
        }
    }

    private struct CalendarDate {
        var year: Int
        var month: Int
        var day: Int
    }

    private static func calendarDate(
        _ text: String,
        order: ImportDateOrder,
        months: ImportMonthNames,
    ) -> CalendarDate? {
        let parts = text.split { "/-. ,".contains($0) }.map(String.init)
        let date: CalendarDate?
        if parts.count == 1 {
            date = compactDate(parts[0])
        } else if parts.count != 3 {
            return nil
        } else if let named = parts.firstIndex(where: { months.month($0) != nil }),
            let month = months.month(parts[named])
        {
            date = namedMonthDate(parts, month: month, at: named)
        } else {
            date = numericDate(parts, order: order)
        }
        guard let date, (1...12).contains(date.month), date.day >= 1,
            date.day <= daysIn(month: date.month, year: date.year)
        else {
            return nil
        }
        return date
    }

    /// `20261105`: always year, month, day, whatever the order (D387.6).
    private static func compactDate(_ text: String) -> CalendarDate? {
        guard text.count == 8, text.allSatisfy(\.isASCIIDigit), let value = Int(text) else {
            return nil
        }
        return CalendarDate(year: value / 10_000, month: value / 100 % 100, day: value % 100)
    }

    /// `20 Oct 2026`, `Oct 20, 2026` or `2026 Oct 20`.
    private static func namedMonthDate(_ parts: [String], month: Int, at named: Int) -> CalendarDate? {
        let numbers = parts.enumerated().filter { $0.offset != named }.map(\.element)
        guard numbers.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }) else {
            return nil
        }
        if numbers[0].count == 4 {
            guard let year = Int(numbers[0]), let day = Int(numbers[1]), numbers[1].count <= 2 else {
                return nil
            }
            return CalendarDate(year: year, month: month, day: day)
        }
        guard numbers[0].count <= 2, let day = Int(numbers[0]), let year = fullYear(numbers[1]) else {
            return nil
        }
        return CalendarDate(year: year, month: month, day: day)
    }

    private static func numericDate(_ parts: [String], order: ImportDateOrder) -> CalendarDate? {
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }) else {
            return nil
        }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3 else {
            return nil
        }
        switch order {
        case .yearMonthDay:
            guard parts[0].count == 4, parts[1].count <= 2, parts[2].count <= 2 else { return nil }
            return CalendarDate(year: numbers[0], month: numbers[1], day: numbers[2])
        case .dayMonthYear:
            guard parts[0].count <= 2, parts[1].count <= 2, let year = fullYear(parts[2]) else { return nil }
            return CalendarDate(year: year, month: numbers[1], day: numbers[0])
        case .monthDayYear:
            guard parts[0].count <= 2, parts[1].count <= 2, let year = fullYear(parts[2]) else { return nil }
            return CalendarDate(year: year, month: numbers[0], day: numbers[1])
        }
    }

    private static func fullYear(_ text: String) -> Int? {
        guard let value = Int(text) else {
            return nil
        }
        switch text.count {
        case 4: return value
        case 2: return 2000 + value
        default: return nil
        }
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }
}
