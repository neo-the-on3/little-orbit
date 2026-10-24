import Foundation
import LittleOrbitDomain

/// The refund sheet's wording, from the final #34 designs (D65, D33, D35, D97.4). Each shape is one whole phrase
/// in the String Catalog with a translator comment, so nothing is joined in code.
enum RefundFormText {
    /// The iOS "Refund of" value: "Trailhead Sports · 17 Oct".
    static func expense(_ name: String, day: String) -> String {
        FeatureText.format("%1$@ · %2$@", name, day)
    }

    /// The iOS "Refundable" value: "₹700.00 of ₹1,000.00".
    static func refundable(_ refundable: String, of total: String) -> String {
        FeatureText.format("%1$@ of %2$@", refundable, total)
    }

    /// The iOS footnote under "Refund of" and "Refundable".
    static func footnote(refunded: String?) -> String {
        guard let refunded else {
            return FeatureText.string(
                "A refund keeps the expense’s category and uses the same currency.",
                comment: "Refund sheet footnote when nothing has been refunded on the expense yet.",
            )
        }
        return FeatureText.format(
            "%@ has already been refunded. A refund keeps the expense’s category and uses the same currency.",
            refunded,
        )
    }

    /// The macOS sheet's caption: "Refund of Trailhead Sports · 17 Oct 2026 · ₹1,000.00 · ₹300.00 already
    /// refunded", without the last part when nothing has been refunded yet.
    static func caption(name: String, day: String, amount: String, refunded: String?) -> String {
        guard let refunded else {
            return FeatureText.format("Refund of %1$@ · %2$@ · %3$@", name, day, amount)
        }
        return FeatureText.format("Refund of %1$@ · %2$@ · %3$@ · %4$@ already refunded", name, day, amount, refunded)
    }

    /// After the macOS Amount field: "of ₹700.00 refundable".
    static func amountSuffix(_ refundable: String) -> String {
        FeatureText.format("of %@ refundable", refundable)
    }

    /// The macOS Category value: "Shopping (from the expense)".
    static func categoryFromExpense(_ name: String) -> String {
        FeatureText.format("%@ (from the expense)", name)
    }

    /// An account in another currency than the expense, in the Account picker: "Travel Card (USD)".
    static func otherCurrencyAccount(_ name: String, currencyCode: String) -> String {
        FeatureText.format("%1$@ (%2$@)", name, currencyCode)
    }

    /// The messages under the form, in its order (D35, D33, D97.4). Nothing to refund and a missing amount show
    /// no message: the Refundable row says ₹0.00, and Save stays disabled.
    static func message(for issue: RefundIssue, currencyCode: String, formatter: MoneyFormatter, text: TransactionText)
        -> String?
    {
        switch issue {
        case .exceedsRefundable(let limit):
            FeatureText.format("Only %@ is refundable.", formatter.string(limit, currencyCode: currencyCode))
        case .currencyMismatch:
            FeatureText.string(
                "Refund currency must match the expense.",
                comment: "Refund sheet: the chosen account is in another currency than the expense (D33).",
            )
        case .dateBeforeOriginal(let day):
            FeatureText.format("Refund date can’t be before the original expense (%@).", text.fullDate(day))
        case .amountMissing, .nothingRefundable:
            nil
        }
    }
}
