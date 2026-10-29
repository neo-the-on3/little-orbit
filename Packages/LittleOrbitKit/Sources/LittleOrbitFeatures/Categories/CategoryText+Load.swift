import Foundation

extension CategoryText {
    /// The category list couldn't be read (D299). OK only, with “Try again.” as its message.
    static var couldntLoadTitle: String {
        FeatureText.string(
            "Couldn’t Load Categories",
            comment:
                "Alert title: the category list, on the Categories screen or in the transaction form’s category picker, couldn’t be read. Its only button is OK.",
        )
    }

    static var tryAgain: String {
        FeatureText.string(
            "Try again.",
            comment:
                "Message under “Couldn’t Load Payees” or “Couldn’t Load Categories” (alerts), under “Couldn’t Load Report” (the spending report and its drill-down), and under “Couldn’t Load Transactions” (search).",
        )
    }
}
