import Foundation
import LittleOrbitDomain

/// The wording of occurrence edits (#197 item 3; #26 D45, D59, D106): the Due Date row and the question Save asks
/// when fields other than the SERIES ones changed (D114, D115). The same strings on iOS and the Mac.
extension ScheduledText {
    static var dueDate: String {
        FeatureText.string(
            "Due Date",
            comment:
                "Scheduled item form, opened on one occurrence of a repeating item: the day that occurrence is due.",
        )
    }

    /// "Save Changes to Gym · FitOrbit?" (D346: title case)
    static func editScopeTitle(_ name: String) -> String {
        FeatureText.format("Save Changes to %@?", name)
    }

    /// "Change only the 18 Oct occurrence, or 18 Oct and every later one?"
    static func editScopeMessage(_ date: String) -> String {
        FeatureText.format("Change only the %1$@ occurrence, or %1$@ and every later one?", date)
    }

    static var thisOccurrenceOnly: String {
        FeatureText.string(
            "This occurrence only",
            comment:
                "Button in the question Save asks for a repeating scheduled item: change only the edited occurrence (D45, D59). The Mac’s default button.",
        )
    }

    static var allFutureOccurrences: String {
        FeatureText.string(
            "All future occurrences",
            comment:
                "Button in the question Save asks for a repeating scheduled item: change the edited occurrence and every later one (D45, D59).",
        )
    }

    /// “Can’t Move to 1 Sep” with “Rent already has an occurrence on 1 Sep. Pick another day, or change that
    /// occurrence first.”: a new Due Date the item already has an occurrence on (D381.1). OK only.
    static func cantMove(_ name: String, to date: String) -> CategoryAlert {
        CategoryAlert(
            title: FeatureText.format("Can’t Move to %@", date),
            message: FeatureText.format(
                "%1$@ already has an occurrence on %2$@. Pick another day, or change that occurrence first.",
                name,
                date,
            ),
        )
    }

    /// “Couldn’t Save Changes” with “Rent has changed since then. Nothing was changed.”: the occurrence was paid or
    /// skipped in another window after the form opened (D381.2). OK only; the stale-step message, no new copy.
    static func changedNothingSaved(_ name: String) -> CategoryAlert {
        CategoryAlert(title: CategoryText.couldntSaveTitle, message: StaleText.changed(name))
    }

    /// “Couldn’t Save Changes” with “JPY Wallet is in Japanese Yen, so it can’t pay this Indian Rupee payment.
    /// Nothing was changed.”: the save moved From into a currency it can't pay an occurrence in (#202 B2, UI
    /// Designer). `name` is From's; the currency names are the locale's. OK only.
    static func cantPayInCurrency(
        _ name: String,
        _ mismatch: ScheduledCurrencyMismatch,
        locale: Locale,
    ) -> CategoryAlert {
        CategoryAlert(
            title: CategoryText.couldntSaveTitle,
            message: FeatureText.format(
                "%1$@ is in %2$@, so it can’t pay this %3$@ payment. Nothing was changed.",
                name,
                CurrencyTitle.name(for: mismatch.accountCurrencyCode, locale: locale),
                CurrencyTitle.name(for: mismatch.paymentCurrencyCode, locale: locale),
            ),
        )
    }
}
