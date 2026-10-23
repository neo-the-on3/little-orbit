import Foundation
import LittleOrbitDomain

/// VoiceOver names for the bulk edit sheet's toggles, so each reads apart from its field: "Change Category"
/// for the toggle, then "Category" for the picker (#110, UI Designer). The visible text stays the field name.
enum BulkEditText {
    static var changeCategory: String {
        FeatureText.string(
            "Change Category",
            comment: "Bulk edit: VoiceOver name of the toggle that turns on Category.",
        )
    }

    static var changePayee: String {
        FeatureText.string("Change Payee", comment: "Bulk edit: VoiceOver name of the toggle that turns on Payee.")
    }

    static var changeDescription: String {
        FeatureText.string(
            "Change Description",
            comment: "Bulk edit: VoiceOver name of the toggle that turns on Description.",
        )
    }

    static var changeDate: String {
        FeatureText.string("Change Date", comment: "Bulk edit: VoiceOver name of the toggle that turns on Date.")
    }

    static var changeAccount: String {
        FeatureText.string("Change Account", comment: "Bulk edit: VoiceOver name of the toggle that turns on Account.")
    }

    /// The Category popup when the selection includes a refund (D222.4).
    static var includesRefunds: String {
        FeatureText.string(
            "Includes refunds",
            comment: "Bulk edit: the Category popup, unavailable because the selection includes a refund.",
        )
    }

    static var refundsKeepCategory: String {
        FeatureText.string(
            "Category is unavailable because the selection includes a refund. A refund keeps its expense’s category.",
            comment: "Bulk edit: footnote when the selection includes a refund, so Category is unavailable (D222.4).",
        )
    }

    /// The Account popup when the selected rows are in more than one currency (D223.2, D226.3).
    static var mixedCurrencies: String {
        FeatureText.string(
            "Mixed currencies",
            comment: "Bulk edit: the Account popup, unavailable because the selected rows are in different currencies.",
        )
    }

    /// The subtitle of an account that is a selected transfer's To account (D223.2).
    static var ownToAccount: String {
        FeatureText.string(
            "To account of a selected transfer",
            comment: "Bulk edit: subtitle of a disabled account in the Account popup: a selected transfer goes to it.",
        )
    }

    /// The subtitle of an account in another currency: "Not in INR" (D226.3).
    static func notIn(_ currencyCode: String) -> String {
        FeatureText.format("Not in %@", currencyCode)
    }

    static var accountRule: String {
        FeatureText.string(
            "Transactions can only move to an account in the same currency.",
            comment:
                "Bulk edit: footnote under Account when an account is disabled or Account is unavailable (D226.3).",
        )
    }

    static var accountRuleWithTransfer: String {
        FeatureText.string(
            "Transactions can only move to an account in the same currency. A transfer can’t move to its own To account.",
            comment: "Bulk edit: footnote under Account, as above, when the selection includes a transfer (D226.3).",
        )
    }

    /// The message when Apply saved nothing because a row breaks a rule (D223.3, D225.5, D226.4, D227.2). The
    /// popup normally prevents the Account cases, so those are the fallback, also when the rows change while the
    /// sheet is open (D227.3). `accounts` names the chosen account; `text` writes the deciding day.
    static func message(
        for rejection: BulkEditRejection,
        accounts: [Account],
        text: TransactionText = TransactionText(locale: .current),
    ) -> String {
        switch rejection {
        case .expenseAfterRefunds(let count, let earliestRefund):
            FeatureText.pluralFormat(
                "Date can’t be after the refunds of %2$lld transactions (earliest %1$@).",
                one: "Date can’t be after its refunds (%1$@).",
                count: count,
                text.fullDate(earliestRefund),
                count,
            )
        case .refundBeforeExpense(let count, let latestExpense):
            FeatureText.pluralFormat(
                "Refund date can’t be before the original expense for %2$lld refunds (latest %1$@).",
                one: "Refund date can’t be before the original expense (%1$@).",
                count: count,
                text.fullDate(latestExpense),
                count,
            )
        case .ownToAccount(let count, let accountID):
            FeatureText.pluralFormat(
                "%1$@ is already the To account of %2$lld selected transfers. Pick a different account to save.",
                one: "%1$@ is already the To account of a selected transfer. Pick a different account to save.",
                count: count,
                name(of: accountID, in: accounts),
                count,
            )
        case .otherCurrency(let count, let currencyCode, let accountID):
            FeatureText.pluralFormat(
                "%3$lld selected transactions are in %1$@, so they can’t move to %2$@. Pick an account in %1$@ to save.",
                one: "A selected transaction is in %1$@, so it can’t move to %2$@. Pick an account in %1$@ to save.",
                count: count,
                currencyCode,
                name(of: accountID, in: accounts),
                count,
            )
        case .mixedCurrencies(let count, let currencyCode, let accountID):
            FeatureText.pluralFormat(
                "%3$lld selected transactions aren’t in %1$@, so they can’t move to %2$@. Select transactions in one currency to change Account.",
                one:
                    "A selected transaction isn’t in %1$@, so it can’t move to %2$@. Select transactions in one currency to change Account.",
                count: count,
                currencyCode,
                name(of: accountID, in: accounts),
                count,
            )
        }
    }

    private static func name(of accountID: UUID, in accounts: [Account]) -> String {
        accounts.first { $0.id == accountID }?.name ?? ""
    }
}
