import Foundation
import LittleOrbitDomain

/// A scheduled transfer between currencies (#197 item 9), reusing #23's cross-currency transfer: when To is in
/// another currency, a Received amount appears with the read-only rate worked out from the two amounts, and the
/// item keeps both (D17, S4). Each occurrence then records both.
extension ScheduledFormViewModel {
    /// Whether To is in another currency than From, so the form asks for the amount received.
    public var needsReceivedAmount: Bool {
        guard type == .transfer, let source = listing.account(accountID),
            let target = listing.account(transferAccountID)
        else {
            return false
        }
        return source.currencyCode != target.currencyCode
    }

    public var receivedLabel: String { ScheduledText.received }

    /// To's currency code, the Received field's prompt.
    public var receivedCurrencyCode: String? {
        listing.account(transferAccountID)?.currencyCode
    }

    /// "1 USD = ₹83.33 · worked out from the two amounts", read-only (D17); `nil` until both amounts read.
    public var rateText: String? {
        guard needsReceivedAmount, let destination = receivedCurrencyCode,
            let sent = try? AmountInput.parse(amountText, currencyCode: currencyCode, locale: locale),
            let received = try? AmountInput.parse(receivedText, currencyCode: destination, locale: locale),
            let rate = TransferRate.unitRate(sent: sent, received: received, sourceCurrency: currencyCode)
        else {
            return nil
        }
        let unit = MoneyFormatter(locale: locale).string(rate, currencyCode: currencyCode)
        return ScheduledText.rate(destination, unit)
    }

    /// The amount received, or `nil` with `receivedError` set: it must be above zero, in To's decimals.
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

    /// An edited item's received amount, as its field shows it in To's currency.
    static func receivedText(of item: ScheduledItem?, listing: ScheduledListing, locale: Locale) -> String {
        guard let item, let received = item.destinationAmount,
            let code = listing.account(item.transferAccountID)?.currencyCode
        else {
            return ""
        }
        return MoneyFormatter(locale: locale).inputString(received, currencyCode: code)
    }
}
