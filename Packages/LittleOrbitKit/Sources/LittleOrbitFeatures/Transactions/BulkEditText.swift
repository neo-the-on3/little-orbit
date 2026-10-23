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

    /// The message when Apply saved nothing because the chosen account breaks a rule (D223.3, D226.4). The
    /// popup normally prevents it, so this is the fallback, also when the rows change while the sheet is open
    /// (D227.2). `accounts` names the chosen account.
    static func message(for rejection: BulkEditRejection, accounts: [Account]) -> String {
        switch rejection {
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
