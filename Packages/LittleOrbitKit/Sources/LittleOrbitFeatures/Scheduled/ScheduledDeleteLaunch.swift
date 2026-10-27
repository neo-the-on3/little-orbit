#if DEBUG
    import Foundation
    import LittleOrbitDomain

    /// A testing hook in Debug builds only (#258): `-LittleOrbitDeleteScheduledItemName <name>` with
    /// `-LittleOrbitDeleteScheduledItemAfter <seconds>` deletes the scheduled item the list calls `name`, that long
    /// after launch, as Delete in another window would. On iPhone and iPad an Edit form can be opened first, which
    /// Tester can't do and then switch scenes by click while the sheet is up. Release builds have none of it, and
    /// the name is never logged.
    public enum ScheduledDeleteLaunch {
        /// The name argument's name.
        public static let nameArgument = "-LittleOrbitDeleteScheduledItemName"
        /// The delay argument's name.
        public static let delayArgument = "-LittleOrbitDeleteScheduledItemAfter"
        private static let longestDelaySeconds: Double = 600

        /// The name the arguments give, trimmed, or nil when it's absent or blank.
        public static func name(in arguments: [String]) -> String? {
            guard let index = arguments.firstIndex(of: nameArgument), index + 1 < arguments.endIndex else {
                return nil
            }
            let name = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }

        /// Whole or decimal seconds above zero, capped at 10 minutes; nil when absent or not such a number.
        public static func delay(in arguments: [String]) -> Duration? {
            guard let index = arguments.firstIndex(of: delayArgument), index + 1 < arguments.endIndex,
                let seconds = Double(arguments[index + 1]), seconds.isFinite, seconds > 0
            else {
                return nil
            }
            return .milliseconds(Int((min(seconds, longestDelaySeconds) * 1000).rounded()))
        }

        @MainActor private static var isTaken = false

        /// This launch's delete, once, and only with both arguments: later calls get nil.
        @MainActor
        public static func take(arguments: [String] = ProcessInfo.processInfo.arguments) -> (
            name: String, delay: Duration
        )? {
            guard !isTaken else {
                return nil
            }
            isTaken = true
            guard let name = name(in: arguments), let delay = delay(in: arguments) else {
                return nil
            }
            return (name, delay)
        }
    }

    extension ScheduledFeature {
        /// Starts this launch's `ScheduledDeleteLaunch` delete, if the arguments ask for one.
        public func startLaunchDelete(arguments: [String] = ProcessInfo.processInfo.arguments) {
            guard let request = ScheduledDeleteLaunch.take(arguments: arguments) else {
                return
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: request.delay)
                self?.deleteItem(named: request.name)
            }
        }

        /// Deletes the first item, in the list's order, whose name or short name on the list is `name`, through a
        /// list model of its own, as Delete in another window: the delete use case, then every window reloads.
        /// Whether one was deleted; an unknown name changes nothing.
        @discardableResult
        func deleteItem(named name: String) -> Bool {
            let list = makeList()
            list.load()
            let board = list.listing.board
            let presenter = ScheduledPresenter(listing: list.listing, locale: locale)
            let items = (board.overdue + board.dueToday + board.upcoming).map(\.item) + board.completed
            guard
                let item = items.first(where: { presenter.shortName(of: $0) == name || presenter.name(of: $0) == name })
            else {
                return false
            }
            list.confirmDelete(item.id)
            list.confirm()
            return list.listing.item(item.id) == nil
        }
    }
#endif
