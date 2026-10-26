#if DEBUG
    import Foundation
    import LittleOrbitDomain

    /// A testing hook in Debug builds only: `-LittleOrbitWatchNotices <value>` at launch puts watch request notices
    /// in the iPhone's real notice store, against scheduled items already in the ledger, so the real Scheduled card
    /// shows without a watch refusing anything (UI Designer 6407485986). They're IDs only, like real ones. Release
    /// builds have none of it. Nothing is logged.
    ///
    /// Each launch with the argument replaces the pending notices, so the card is back after OK on the next launch.
    /// With no active scheduled item nothing is seeded. Items are used in the ledger's order, repeating when there
    /// are fewer than the preset needs.
    ///
    /// - `refused-pay`: one Pay refused on save (D378), a single card with View Item and OK.
    /// - `refused-skip`: the same for a Skip.
    /// - `mixed`: an item-changed Pay and a refused Skip, one grouped card with the mixed wording (D379).
    /// - `refused-group`: three refused actions, one grouped card with the refused wording (D379).
    public enum WatchNoticesLaunchPreset: String, CaseIterable, Sendable {
        case refusedPay = "refused-pay"
        case refusedSkip = "refused-skip"
        case mixed
        case refusedGroup = "refused-group"

        /// The launch argument's name.
        public static let argument = "-LittleOrbitWatchNotices"

        /// The preset the arguments name, or nil when the argument is absent, has no value after it, or names
        /// none of the presets. Values are matched exactly.
        public static func preset(in arguments: [String]) -> Self? {
            guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.endIndex else {
                return nil
            }
            return Self(rawValue: arguments[index + 1])
        }

        /// The notices this preset seeds against these items, or none with no items.
        func notices(itemIDs: [UUID], makeID: () -> UUID = UUID.init) -> [WatchRequestNotice] {
            guard !itemIDs.isEmpty else {
                return []
            }
            let shape: [(WatchRequestNotice.Reason, WatchScheduledRequest.Action)] =
                switch self {
                case .refusedPay: [(.refusedOnSave, .pay)]
                case .refusedSkip: [(.refusedOnSave, .skip)]
                case .mixed: [(.itemChanged, .pay), (.refusedOnSave, .skip)]
                case .refusedGroup: [(.refusedOnSave, .pay), (.refusedOnSave, .skip), (.refusedOnSave, .pay)]
                }
            return shape.enumerated()
                .map { index, entry in
                    WatchRequestNotice(
                        id: makeID(),
                        reason: entry.0,
                        action: entry.1,
                        itemID: itemIDs[index % itemIDs.count],
                    )
                }
        }

        /// Seeds this launch's preset, if the arguments name one, into `inbox`. Call it before the notice card's
        /// model first reads the store.
        @MainActor
        public static func seed(
            arguments: [String] = ProcessInfo.processInfo.arguments,
            repository: any ScheduleRepository,
            inbox: any WatchRequestInboxStore,
        ) {
            guard let preset = preset(in: arguments), let ledger = try? repository.scheduleLedger() else {
                return
            }
            let itemIDs = LedgerBook.activeScheduledItems(in: ledger).map(\.id)
            guard !itemIDs.isEmpty else {
                return
            }
            inbox.setNotices(preset.notices(itemIDs: itemIDs))
        }
    }
#endif
