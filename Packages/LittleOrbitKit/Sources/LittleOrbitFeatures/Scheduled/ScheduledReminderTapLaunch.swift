#if DEBUG
    import Foundation

    /// A testing hook in Debug builds only (S33): `-LittleOrbitScheduledReminderTap <scheduled item ID>` at launch
    /// acts as a tap on that item's reminder, because the simulator's notification banners can't be tapped. The App
    /// hands the ID to the same handler a real notification response reaches, once launch and the first catch-up
    /// are done, with no window named, as on a cold launch. Release builds have none of it. The ID is never logged.
    /// With `-LittleOrbitScheduledReminderTapAfter <seconds>` as well, the tap comes that long after launch instead,
    /// a warm tap, so a sheet can be opened and edited first on iPhone and iPad, which have no Debug menu to tap.
    /// `-LittleOrbitScheduledReminderSecondTap <ID>` and `-LittleOrbitScheduledReminderSecondTapAfter <seconds>` add
    /// a second tap, on another item if wanted, with its own delay from launch, for two taps in a row (Tester's B2).
    public enum ScheduledReminderTapLaunch {
        /// One tap the launch arguments ask for: the item, and how long after launch, if not straight away.
        public struct Tap: Equatable, Sendable {
            public let itemID: UUID
            public let delay: Duration?
        }

        /// The launch argument's name.
        public static let argument = "-LittleOrbitScheduledReminderTap"
        /// The delay argument's name.
        public static let delayArgument = "-LittleOrbitScheduledReminderTapAfter"
        /// The second tap's argument name.
        public static let secondArgument = "-LittleOrbitScheduledReminderSecondTap"
        /// The second tap's delay argument name.
        public static let secondDelayArgument = "-LittleOrbitScheduledReminderSecondTapAfter"
        /// The longest delay taken, so a typo can't leave a tap waiting all session.
        public static let longestDelay: Duration = .seconds(longestDelaySeconds)
        private static let longestDelaySeconds: Double = 600

        /// The item `name` names, or nil when the argument is absent or isn't followed by a UUID.
        public static func itemID(in arguments: [String], named name: String = argument) -> UUID? {
            guard let index = arguments.firstIndex(of: name), index + 1 < arguments.endIndex else {
                return nil
            }
            return UUID(uuidString: arguments[index + 1])
        }

        /// How long after launch to tap: whole or decimal seconds above zero, up to `longestDelay`. Nil when the
        /// argument is absent or its value isn't such a number, so the tap comes straight after launch.
        public static func delay(in arguments: [String], named name: String = delayArgument) -> Duration? {
            guard let index = arguments.firstIndex(of: name), index + 1 < arguments.endIndex,
                let seconds = Double(arguments[index + 1]), seconds.isFinite, seconds > 0
            else {
                return nil
            }
            // Capped as a Double first, so a huge value like 1e16 can't overflow the Int conversion.
            let capped = min(seconds, longestDelaySeconds)
            return .milliseconds(Int((capped * 1000).rounded()))
        }

        /// The taps the arguments ask for: the first tap, then the second, each only when its item is given.
        public static func taps(in arguments: [String]) -> [Tap] {
            var taps: [Tap] = []
            for (name, delayName) in [(argument, delayArgument), (secondArgument, secondDelayArgument)] {
                if let itemID = itemID(in: arguments, named: name) {
                    taps.append(Tap(itemID: itemID, delay: delay(in: arguments, named: delayName)))
                }
            }
            return taps
        }

        @MainActor private static var isTaken = false

        /// This launch's taps, once: later calls get none, so building the App's features again doesn't tap twice.
        @MainActor
        public static func take(arguments: [String] = ProcessInfo.processInfo.arguments) -> [Tap] {
            guard !isTaken else {
                return []
            }
            isTaken = true
            return taps(in: arguments)
        }
    }
#endif
