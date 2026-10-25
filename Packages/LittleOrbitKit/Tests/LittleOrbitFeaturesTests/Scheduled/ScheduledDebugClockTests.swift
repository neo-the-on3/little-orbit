#if DEBUG
    import Foundation
    import LittleOrbitDomain
    import LittleOrbitFeatures
    import Testing

    /// D337.2: the DEBUG-only launch argument that moves "today" for scheduled items.
    @MainActor
    @Suite("Scheduled debug date (D337.2)")
    struct ScheduledDebugClockTests {
        private let kolkata = TimeZone(identifier: "Asia/Kolkata")!

        @Test("The argument takes an ISO day; anything else is ignored")
        func parsing() {
            let argument = ScheduledDebugClock.argument
            #expect(argument == "-LittleOrbitScheduledToday")
            #expect(
                ScheduledDebugClock.overriddenDay(in: ["app", argument, "2026-11-20"])
                    == CalendarDay(year: 2026, month: 11, day: 20)
            )
            #expect(ScheduledDebugClock.overriddenDay(in: ["app"]) == nil)
            #expect(ScheduledDebugClock.overriddenDay(in: ["app", argument]) == nil)
            #expect(ScheduledDebugClock.overriddenDay(in: ["app", argument, "2026-02-30"]) == nil)
            #expect(ScheduledDebugClock.overriddenDay(in: ["app", argument, "20/11/2026"]) == nil)
            #expect(ScheduledDebugClock.overriddenDay(in: ["app", argument, "2026-1-5"]) == nil)
        }

        @Test("The clock reads the chosen day, keeps the time running, and dates new items on it")
        func clock() throws {
            let zone = kolkata
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let launch = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 15)))
            let real = RealClock(launch)
            let clock = ScheduledDebugClock.clock(
                today: CalendarDay(year: 2027, month: 2, day: 2),
                launchedAt: launch,
                timeZone: { zone },
                now: { real.date },
            )
            #expect(TransactionTiming.today(clock(), timeZone: zone) == CalendarDay(year: 2027, month: 2, day: 2))
            #expect(calendar.component(.hour, from: clock()) == 15)
            real.date = launch.addingTimeInterval(10 * 3_600)
            #expect(TransactionTiming.today(clock(), timeZone: zone) == CalendarDay(year: 2027, month: 2, day: 3))
            // Back in time works too, for creating an item "earlier" and relaunching later.
            let past = ScheduledDebugClock.clock(
                today: CalendarDay(year: 2026, month: 8, day: 1),
                launchedAt: launch,
                timeZone: { zone },
                now: { launch },
            )
            #expect(TransactionTiming.today(past(), timeZone: zone) == CalendarDay(year: 2026, month: 8, day: 1))
        }
    }

    /// The "real" clock the debug clock reads, moved forward by the test.
    @MainActor
    private final class RealClock {
        var date: Date
        init(_ date: Date) { self.date = date }
    }
#endif
