import Foundation
import LittleOrbitDomain

/// Pay with a custom date or amount on a transfer between currencies (#207, second-lander gate on #201): the sheet
/// asks for the amount received, prefilled with the item's, and records it with To's currency code, so a custom
/// amount sent never keeps the old amount received and #207's store check still holds.
extension ScheduledPayViewModel {
    /// Whether From, as chosen, is in another currency than To, so the sheet asks for the amount received.
    public var needsReceivedAmount: Bool {
        guard item.type == .transfer, let source = listing.account(accountID),
            let target = listing.account(item.transferAccountID)
        else {
            return false
        }
        return source.currencyCode != target.currencyCode
    }

    public var receivedLabel: String { ScheduledText.received }

    /// To's currency code, the Received field's prompt.
    public var receivedCurrencyCode: String? {
        listing.account(item.transferAccountID)?.currencyCode
    }

    /// "Enter the amount received in USD.", a plain hint under Received while it's required and empty.
    public var receivedHint: String? {
        guard needsReceivedAmount, receivedText.trimmingCharacters(in: .whitespaces).isEmpty,
            let code = receivedCurrencyCode
        else {
            return nil
        }
        return ScheduledText.enterReceived(code)
    }

    /// The amount received, or `nil` with `receivedError` set: above zero, in To's decimals, as on the form.
    func parseReceived() -> Decimal? {
        guard let code = receivedCurrencyCode else {
            return nil
        }
        let received: Decimal
        do {
            received = try AmountInput.parse(receivedText, currencyCode: code, locale: locale)
        } catch .tooManyDecimals(let allowed) {
            receivedError = ScheduledText.tooManyDecimals(allowed, currencyCode: code)
            return nil
        } catch {
            receivedError =
                receivedText.trimmingCharacters(in: .whitespaces).isEmpty
                ? ScheduledText.enterReceived(code)
                : ScheduledText.enterAmountLike(MoneyFormatter(locale: locale).exampleAmount(currencyCode: code))
            return nil
        }
        guard received > 0 else {
            receivedError = ScheduledText.enterReceived(code)
            return nil
        }
        return received
    }
}
