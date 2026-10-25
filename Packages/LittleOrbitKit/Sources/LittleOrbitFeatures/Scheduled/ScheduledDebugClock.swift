#if DEBUG
    import Foundation
    import LittleOrbitDomain

    /// DEBUG builds only (D337.2): a launch argument that moves "today" for the scheduled items, so Tester can set up
    /// overdue and catch-up states in the simulator, which follows the Mac's clock. It isn't compiled into release
    /// builds. The App feeds it through the clock it injects into the scheduled use cases, so new items are created
    /// on that day too; Domain still never reads the clock itself.
    ///
    /// `-LittleOrbitScheduledToday 2026-11-20` (ISO year-month-day). Time of day keeps running from the real clock.
    public enum ScheduledDebugClock {
        public static let argument = "-LittleOrbitScheduledToday"

        /// The day after `argument` in `arguments`, or `nil` when it's missing or isn't a real day.
        public static func overriddenDay(in arguments: [String]) -> CalendarDay? {
            guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else {
                return nil
            }
            let parts = arguments[index + 1].split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
                let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
            else {
                return nil
            }
            let result = CalendarDay(year: year, month: month, day: day)
            return ScheduleCalendar.isValid(result) ? result : nil
        }

        /// `now`, moved by whole days so that, read in `timeZone`, it falls on `day` when the app launched.
        @MainActor
        public static func clock(
            today day: CalendarDay,
            launchedAt launch: Date,
            timeZone: @escaping @MainActor () -> TimeZone,
            now: @escaping @MainActor () -> Date,
        ) -> @MainActor () -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
            let real = TransactionTiming.today(launch, timeZone: timeZone())
            let offset =
                calendar.dateComponents(
                    [.day],
                    from: ScheduledDebugClock.noon(real, calendar),
                    to: ScheduledDebugClock.noon(day, calendar),
                )
                .day ?? 0
            return {
                var local = Calendar(identifier: .gregorian)
                local.timeZone = timeZone()
                let current = now()
                return local.date(byAdding: .day, value: offset, to: current) ?? current
            }
        }

        private static func noon(_ day: CalendarDay, _ calendar: Calendar) -> Date {
            calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
                ?? .distantPast
        }
    }
#endif
