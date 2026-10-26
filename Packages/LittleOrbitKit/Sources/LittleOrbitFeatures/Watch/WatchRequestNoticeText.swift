import Foundation

/// The Scheduled list's card for watch Pay and Skip requests the iPhone didn't apply (D374, D375, D376), from the
/// package's String Catalog. Each sentence is its own entry; the counts are whole-phrase plurals.
enum WatchRequestNoticeText {
    // MARK: The item changed on the iPhone first (D374, D375)

    static var payTitle: String {
        FeatureText.string(
            "Couldn’t Record Watch Payment",
            comment:
                "iPhone Scheduled list, card title: a Pay tapped on the Apple Watch recorded nothing, because the scheduled item was changed on the iPhone before the Pay arrived.",
        )
    }

    static var skipTitle: String {
        FeatureText.string(
            "Couldn’t Skip From Watch",
            comment:
                "iPhone Scheduled list, card title: a Skip tapped on the Apple Watch skipped nothing, because the scheduled item was changed on the iPhone before the Skip arrived.",
        )
    }

    /// "Rent changed on iPhone before this arrived from your Apple Watch, so nothing was recorded."
    static func payChanged(_ item: String) -> String {
        FeatureText.format(
            "%@ changed on iPhone before this arrived from your Apple Watch, so nothing was recorded.",
            item,
        )
    }

    static func skipChanged(_ item: String) -> String {
        FeatureText.format(
            "%@ changed on iPhone before this arrived from your Apple Watch, so nothing was skipped.",
            item,
        )
    }

    static var payAgain: String {
        FeatureText.string(
            "Check the item and pay again if you need to.",
            comment:
                "iPhone Scheduled list, card message, second sentence, after a Pay from the Apple Watch recorded nothing: the user can open the scheduled item and pay it on the iPhone.",
        )
    }

    static var skipAgain: String {
        FeatureText.string(
            "Check the item and skip again if you need to.",
            comment:
                "iPhone Scheduled list, card message, second sentence, after a Skip from the Apple Watch skipped nothing: the user can open the scheduled item and skip it on the iPhone.",
        )
    }

    /// Several at once (D375).
    static var severalChangedTitle: String {
        FeatureText.string(
            "Couldn’t Apply Watch Actions",
            comment:
                "iPhone Scheduled list, card title: several Pay or Skip actions tapped on the Apple Watch did nothing, because their scheduled items were changed on the iPhone first.",
        )
    }

    /// "3 watch actions couldn’t be applied because their items changed on iPhone."
    static func severalChanged(_ count: Int) -> String {
        FeatureText.plural(
            "%lld watch actions couldn’t be applied because their items changed on iPhone.",
            one: "%lld watch action couldn’t be applied because its item changed on iPhone.",
            count,
        )
    }

    static var severalChangedAgain: String {
        FeatureText.string(
            "Check those items and try again if you need to.",
            comment:
                "iPhone Scheduled list, card message, second sentence, after several Pay or Skip actions from the Apple Watch did nothing: the user can check the scheduled items on the iPhone.",
        )
    }

    // MARK: A newer watch app (D376)

    static var updateTitle: String {
        FeatureText.string(
            "Update little-orbit on iPhone",
            comment:
                "iPhone Scheduled list, card title: Pay or Skip actions came from a newer version of the Apple Watch app than this iPhone app can read. little-orbit is the app's name.",
        )
    }

    static var payNewer: String {
        FeatureText.string(
            "Your Apple Watch has a newer version of little-orbit, so this payment wasn’t recorded.",
            comment:
                "iPhone Scheduled list, card message, first sentence: a Pay tapped on the Apple Watch recorded nothing, because the watch app is newer than this iPhone app. little-orbit is the app's name.",
        )
    }

    static var payNewerAgain: String {
        FeatureText.string(
            "Update little-orbit on your iPhone, then pay again from your watch or iPhone.",
            comment:
                "iPhone Scheduled list, card message, second sentence, after a Pay from a newer Apple Watch app recorded nothing. little-orbit is the app's name.",
        )
    }

    static var skipNewer: String {
        FeatureText.string(
            "Your Apple Watch has a newer version of little-orbit, so this skip wasn’t recorded.",
            comment:
                "iPhone Scheduled list, card message, first sentence: a Skip tapped on the Apple Watch did nothing, because the watch app is newer than this iPhone app. little-orbit is the app's name.",
        )
    }

    static var skipNewerAgain: String {
        FeatureText.string(
            "Update little-orbit on your iPhone, then skip again from your watch or iPhone.",
            comment:
                "iPhone Scheduled list, card message, second sentence, after a Skip from a newer Apple Watch app did nothing. little-orbit is the app's name.",
        )
    }

    /// "3 watch actions weren’t recorded because your Apple Watch has a newer version of little-orbit."
    static func severalNewer(_ count: Int) -> String {
        FeatureText.plural(
            "%lld watch actions weren’t recorded because your Apple Watch has a newer version of little-orbit.",
            one: "%lld watch action wasn’t recorded because your Apple Watch has a newer version of little-orbit.",
            count,
        )
    }

    static var severalNewerAgain: String {
        FeatureText.string(
            "Update little-orbit on your iPhone, then try again.",
            comment:
                "iPhone Scheduled list, card message, second sentence, after Pay or Skip actions from a newer Apple Watch app did nothing. little-orbit is the app's name.",
        )
    }

    // MARK: Buttons

    static var viewItem: String {
        FeatureText.string(
            "View Item",
            comment:
                "iPhone Scheduled list, card button, after a watch Pay or Skip did nothing: opens the scheduled item.",
        )
    }

    static var okay: String {
        FeatureText.string("OK", comment: "Dismisses the Scheduled list’s card about watch actions for good.")
    }
}
