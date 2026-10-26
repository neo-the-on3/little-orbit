import Foundation

/// The wording of the watch's Scheduled screens (#32, #197 item 10), from the package's String Catalog. The list
/// title, Skip and the empty state are the iPhone's entries.
enum WatchText {
    /// The watch's Pay button (#32 frame 137:734).
    static var pay: String {
        FeatureText.string(
            "Pay",
            comment: "Apple Watch, a scheduled occurrence: records it on the iPhone, dated today.",
        )
    }

    /// The list row of an occurrence due today (#32 frame 137:693).
    static var today: String {
        FeatureText.string(
            "Today",
            comment: "Apple Watch, Scheduled list row: this occurrence is due today.",
        )
    }

    /// The row of an occurrence paid on the watch, until the iPhone confirms it (#32 frame 137:753).
    static var paidSyncing: String {
        FeatureText.string(
            "Paid · syncing",
            comment: "Apple Watch, Scheduled list row: paid on the watch, waiting for the iPhone to record it.",
        )
    }

    /// The row of an occurrence skipped on the watch, until the iPhone confirms it. Pending Product Manager: only
    /// “Paid · syncing” is drawn.
    static var skippedSyncing: String {
        FeatureText.string(
            "Skipped · syncing",
            comment: "Apple Watch, Scheduled list row: skipped on the watch, waiting for the iPhone to apply it.",
        )
    }

    // MARK: Conflicts (D342, D343)

    static var alreadyPaidOnIPhone: String {
        FeatureText.string(
            "Already paid on iPhone",
            comment:
                "Apple Watch message title: a Pay or Skip from the watch did nothing, because this occurrence was already paid on the iPhone.",
        )
    }

    static var alreadySkippedOnIPhone: String {
        FeatureText.string(
            "Already skipped on iPhone",
            comment:
                "Apple Watch message title: a Pay or Skip from the watch did nothing, because this occurrence was already skipped on the iPhone.",
        )
    }

    static var deletedOnIPhone: String {
        FeatureText.string(
            "Deleted on iPhone",
            comment:
                "Apple Watch message title: a Pay or Skip from the watch did nothing, because the scheduled item was deleted on the iPhone.",
        )
    }

    /// "Netflix · 20 Oct.": the message's first sentence, the item and the occurrence's date.
    static func itemOnDate(_ item: String, _ date: String) -> String {
        FeatureText.format("%1$@ · %2$@.", item, date)
    }

    /// After a watch Pay (D343).
    static func payNotRecorded(account: String) -> String {
        FeatureText.format("Your Pay from the watch wasn’t recorded, and %@ is unchanged.", account)
    }

    /// After a watch Skip (D343).
    static var skipNotApplied: String {
        FeatureText.string(
            "Your Skip from the watch wasn’t applied.",
            comment:
                "Apple Watch message, after its title and the item and date: the Skip tapped on the watch did nothing.",
        )
    }

    /// Two sentences of one message, joined.
    static func sentences(_ first: String, _ second: String) -> String {
        FeatureText.format("%1$@ %2$@", first, second)
    }
}
