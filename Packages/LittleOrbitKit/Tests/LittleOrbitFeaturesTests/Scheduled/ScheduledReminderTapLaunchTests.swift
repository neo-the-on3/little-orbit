#if DEBUG
    import Foundation
    import Testing

    @testable import LittleOrbitFeatures

    /// The Debug-only `-LittleOrbitScheduledReminderTap` hook (S33): a reminder tap the simulator can't make.
    @MainActor
    @Suite("Scheduled reminder tap launch argument (#26 S33, Debug only)")
    struct ScheduledReminderTapLaunchTests {
        private let item = UUID()

        @Test("The argument names the item by UUID; anything else is ignored")
        func parsing() {
            let argument = ScheduledReminderTapLaunch.argument
            #expect(argument == "-LittleOrbitScheduledReminderTap")
            #expect(ScheduledReminderTapLaunch.itemID(in: ["app", argument, item.uuidString]) == item)
            #expect(ScheduledReminderTapLaunch.itemID(in: ["app", argument, item.uuidString.lowercased()]) == item)
            #expect(ScheduledReminderTapLaunch.itemID(in: ["app"]) == nil)
            #expect(ScheduledReminderTapLaunch.itemID(in: ["app", argument]) == nil)
            #expect(ScheduledReminderTapLaunch.itemID(in: ["app", argument, ""]) == nil)
            #expect(ScheduledReminderTapLaunch.itemID(in: ["app", argument, "not-a-uuid"]) == nil)
            #expect(ScheduledReminderTapLaunch.itemID(in: ["app", argument, "-LittleOrbitScheduledToday"]) == nil)
            #expect(
                ScheduledReminderTapLaunch.itemID(in: ["app", "-littleorbitscheduledremindertap", item.uuidString])
                    == nil
            )
        }

        @Test("The delay argument takes seconds above zero, up to 10 minutes; anything else means no delay")
        func delayParsing() {
            let delay = ScheduledReminderTapLaunch.delayArgument
            #expect(delay == "-LittleOrbitScheduledReminderTapAfter")
            let tap = [ScheduledReminderTapLaunch.argument, item.uuidString]
            #expect(ScheduledReminderTapLaunch.delay(in: ["app"] + tap + [delay, "20"]) == .seconds(20))
            #expect(ScheduledReminderTapLaunch.delay(in: ["app", delay, "2.5"] + tap) == .milliseconds(2500))
            #expect(ScheduledReminderTapLaunch.delay(in: ["app", delay, "3600"]) == .seconds(600))
            #expect(ScheduledReminderTapLaunch.delay(in: ["app", delay, "1e16"]) == .seconds(600))
            #expect(ScheduledReminderTapLaunch.delay(in: ["app"] + tap) == nil)
            #expect(ScheduledReminderTapLaunch.delay(in: ["app", delay]) == nil)
            for value in ["0", "-5", "", "soon", "nan", "inf", item.uuidString] {
                #expect(ScheduledReminderTapLaunch.delay(in: ["app", delay, value]) == nil)
            }
            // The tap argument's item is read the same with the delay next to it.
            #expect(ScheduledReminderTapLaunch.itemID(in: ["app"] + tap + [delay, "20"]) == item)
        }

        @Test("A second tap, on its own item with its own delay from launch, comes after the first (B2)")
        func secondTap() {
            typealias Launch = ScheduledReminderTapLaunch
            #expect(Launch.secondArgument == "-LittleOrbitScheduledReminderSecondTap")
            #expect(Launch.secondDelayArgument == "-LittleOrbitScheduledReminderSecondTapAfter")
            let other = UUID()
            let first = [Launch.argument, item.uuidString, Launch.delayArgument, "20"]
            let second = [Launch.secondArgument, other.uuidString, Launch.secondDelayArgument, "40"]
            #expect(
                Launch.taps(in: ["app"] + second + first) == [
                    .init(itemID: item, delay: .seconds(20)), .init(itemID: other, delay: .seconds(40)),
                ]
            )
            // Each delay is its own: the second's doesn't change the first's, and either can be absent.
            #expect(
                Launch.taps(in: ["app", Launch.argument, item.uuidString] + second) == [
                    .init(itemID: item, delay: nil), .init(itemID: other, delay: .seconds(40)),
                ]
            )
            #expect(Launch.taps(in: ["app"] + first) == [.init(itemID: item, delay: .seconds(20))])
            #expect(Launch.taps(in: ["app", Launch.secondArgument, "not-a-uuid"]) == [])
            #expect(Launch.taps(in: ["app"]) == [])
            // The Debug menu's tap still reads only the first tap's item.
            #expect(Launch.itemID(in: ["app"] + second) == nil)
        }

        @Test("Taken once per launch, then it reaches a window like a cold-launch tap that names none")
        func takenOnceAndOpened() throws {
            let arguments = ["app", ScheduledReminderTapLaunch.argument, item.uuidString]
            let itemID = try #require(ScheduledReminderTapLaunch.take(arguments: arguments).first?.itemID)
            #expect(ScheduledReminderTapLaunch.take(arguments: arguments).isEmpty)
            // The App's handler reports a tap with no scene; the first window up takes it, once.
            let taps = ScheduledReminderTaps()
            taps.tapped(itemID: itemID, window: nil)
            taps.windowAppeared("1")
            #expect(taps.take(for: "1")?.itemID == item)
            #expect(taps.take(for: "1") == nil)
        }
    }
#endif
