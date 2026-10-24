import Foundation

/// The wording of the iOS Settings › Payees screens (#24), from the package's String Catalog. Words the
/// category screens already use, such as Cancel, Merge and the merge footnote's first and last sentences, are
/// the same entries, as are the editor's name errors and the “Couldn’t Save Changes” alert title.
enum PayeeText {
    // MARK: List

    static var title: String {
        FeatureText.string("Payees", comment: "Settings row and screen title: the payee manager.")
    }

    static var searchPrompt: String {
        FeatureText.string("Search payees", comment: "Payees screen: the search field’s placeholder.")
    }

    /// "Shopping · 40": the payee's last-used category and how many transactions use it.
    static func detail(category: String, count: Int) -> String {
        FeatureText.format("%1$@ · %2$lld", category, count)
    }

    /// "40 transactions": a payee with no last-used category, and the Merge Payees rows.
    static func transactions(_ count: Int) -> String {
        FeatureText.plural("%lld transactions", one: "%lld transaction", count)
    }

    /// VoiceOver's reading of a row's detail: "Shopping, 40 transactions".
    static func spokenDetail(category: String, count: Int) -> String {
        FeatureText.pluralFormat(
            "%1$@, %2$lld transactions",
            one: "%1$@, %2$lld transaction",
            count: count,
            category,
            count,
        )
    }

    static var listFooter: String {
        FeatureText.string(
            "Each payee shows its last-used category and how many transactions use it. Picking a payee on a new transaction preselects its last-used category. To merge duplicates, tap More, then Select.",
            comment:
                "Payees screen footer under the list, outside select mode. More is the toolbar menu; Select is its item.",
        )
    }

    static var emptyTitle: String {
        FeatureText.string("No Payees", comment: "Payees screen with no payees: the title.")
    }

    static var emptyMessage: String {
        FeatureText.string(
            "Payees you enter on transactions appear here.",
            comment: "Payees screen with no payees: the explanation.",
        )
    }

    static var select: String {
        FeatureText.string("Select", comment: "Payees screen menu item: choose payees to merge.")
    }

    /// "2 selected": how many payees are chosen in select mode.
    static func selected(_ count: Int) -> String {
        FeatureText.plural("%lld selected", one: "%lld selected", count)
    }

    static var mergeEllipsis: String {
        FeatureText.string("Merge…", comment: "Payees screen, select mode: opens Merge Payees for the chosen payees.")
    }

    // MARK: Merge (D287.3, D291.5)

    static var mergeTitle: String {
        FeatureText.string("Merge Payees", comment: "Sheet title: merge the chosen payees into one.")
    }

    static var keepWhichName: String {
        FeatureText.string("Keep which name?", comment: "Merge Payees: the header over the payees to keep one of.")
    }

    /// "PARCELPOINT.IN is removed from lists, autocomplete and reports.", with two or more names joined by the
    /// system list format: "Parcel Point and PARCELPOINT.IN are removed…".
    static func removed(_ names: [String]) -> String {
        FeatureText.pluralFormat(
            "%1$@ are removed from lists, autocomplete and reports.",
            one: "%1$@ is removed from lists, autocomplete and reports.",
            count: names.count,
            names.formatted(.list(type: .and)),
            names.count,
        )
    }

    /// "Parcel Point keeps the most recent last-used category (Shopping)." (D291.5)
    static func keepsCategory(payee: String, category: String) -> String {
        FeatureText.format("%1$@ keeps the most recent last-used category (%2$@).", payee, category)
    }

    static var nothingChanged: String {
        FeatureText.string(
            "Your payees weren’t changed. Try again.",
            comment:
                "Alert message under “Couldn’t Save Changes”: a payee rename or merge failed and nothing was saved.",
        )
    }

    /// “Couldn’t Save Changes”: a rename or merge failed and nothing changed (D297.7).
    static var saveFailed: CategoryAlert {
        CategoryAlert(title: CategoryText.couldntSaveTitle, message: nothingChanged)
    }

    /// “Couldn’t Load Payees”: the list couldn't be read (D297.7).
    static var loadFailed: CategoryAlert {
        CategoryAlert(title: couldntLoadTitle, message: tryAgain)
    }

    static var couldntLoadTitle: String {
        FeatureText.string(
            "Couldn’t Load Payees",
            comment: "Alert title: the payee list couldn’t be read. Its only button is OK.",
        )
    }

    static var tryAgain: String {
        CategoryText.tryAgain
    }

    // MARK: Editor

    static var editTitle: String {
        FeatureText.string("Edit Payee", comment: "Payee editor title: renaming a payee.")
    }

    static func duplicateName(_ name: String) -> String {
        FeatureText.string(
            "There’s already a payee named “\(name)”.",
            comment: "Payee editor, under the name field: another payee has this name, ignoring case. The name typed.",
        )
    }
}
