import Foundation

/// A transfer between currencies asks for the amount received, in To's currency (D17). #215 (D446, D368.2) gives
/// the entry and edit sheet #207's scheduled-form rule, so a received amount is never saved in the wrong currency.
extension TransactionFormViewModel {
    /// A typed Received means To's currency, so a To in another currency clears it: "120" can't turn from $120 into
    /// €120. A To in the same currency keeps it, and moving To back doesn't bring the old text back. A To in From's
    /// currency hides the field, and the cleared text means nothing is saved for it (D340.15). Opening an edit sets
    /// To before `isLoaded`, so the saved amount stays.
    func transferAccountChanged(from old: UUID?) {
        guard isLoaded, old != transferAccountID, currencyCode(of: old) != currencyCode(of: transferAccountID) else {
            return
        }
        receivedText = ""
    }

    /// "Enter the amount received in EUR.", a plain hint under Received while it's required and not yet a positive
    /// amount, for example after To's currency changes; Save waits for it. It's #207's catalog entry, so both forms
    /// share one translated string (UI Designer on #215).
    public var receivedHint: String? {
        guard needsReceivedAmount, (receivedAmount ?? 0) <= 0, let code = receivedCurrencyCode else {
            return nil
        }
        return FeatureText.format("Enter the amount received in %@.", code)
    }

    private func currencyCode(of accountID: UUID?) -> String? {
        accounts.first { $0.id == accountID }?.currencyCode
    }
}
