import Foundation

/// The Scheduled form's inline errors (D334.12).
extension ScheduledText {
    static var enterAmount: String {
        FeatureText.string(
            "Enter an amount above zero.",
            comment: "Scheduled form error under the amount: it’s empty or zero.",
        )
    }

    /// "Enter an amount like 1,25,000.00.", with the locale's sample, as on the account form (D334.12).
    static func enterAmountLike(_ sample: String) -> String {
        FeatureText.format("Enter an amount like %@.", sample)
    }

    /// "INR amounts can have up to 2 decimal places." / "JPY amounts have no decimal places." (D334.12)
    static func tooManyDecimals(_ allowed: Int, currencyCode: String) -> String {
        guard allowed > 0 else {
            return FeatureText.format("%@ amounts have no decimal places.", currencyCode)
        }
        return FeatureText.pluralFormat(
            "%1$@ amounts can have up to %2$lld decimal places.",
            one: "%1$@ amounts can have up to %2$lld decimal place.",
            count: allowed,
            currencyCode,
            allowed,
        )
    }

    static var pickAccount: String {
        FeatureText.string("Pick an account.", comment: "Scheduled form error: no account is chosen.")
    }

    static var pickTwoAccounts: String {
        FeatureText.string(
            "Pick two different accounts.",
            comment: "Scheduled transfer form error: From and To are the same or missing.",
        )
    }

    static var endBeforeStart: String {
        FeatureText.string(
            "Pick an end date on or after the start date.",
            comment: "Scheduled form error: the end date is earlier than the start date.",
        )
    }
}
