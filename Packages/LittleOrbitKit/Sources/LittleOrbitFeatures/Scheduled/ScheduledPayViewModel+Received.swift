import Foundation
import LittleOrbitDomain

/// Pay with a custom date or amount on a transfer between currencies (#207, second-lander gate on #201, D415): the
/// sheet asks for the amount received in To's currency, prefilled with the item's amount received when it has one and
/// empty otherwise, never worked out from a rate, and records it with To's currency code, so a custom amount sent
/// never keeps the old amount received and #207's store check still holds. Record waits until both amounts read.
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

    /// Why Received stops Record, as a plain hint under it, or `nil` when it reads (D415): "Enter the amount received
    /// in USD." while it's empty or 0, else the form's message for text it can't read, such as too many decimals.
    public var receivedHint: String? {
        guard needsReceivedAmount, case .failure(let problem) = readReceived() else {
            return nil
        }
        return problem.message
    }

    /// Why Amount stops Record on a transfer between currencies, as a plain hint under it, or `nil` when it reads
    /// (D415). A Pay in one currency keeps its error on Record instead, as before.
    public var amountHint: String? {
        guard needsReceivedAmount, case .failure(let problem) = readAmount() else {
            return nil
        }
        return problem.message
    }

    /// Whether Record is enabled (D415). Between currencies it waits until Amount, in From's currency, and Received,
    /// in To's, both read and are above zero; in one currency it's always enabled, and Record shows any error.
    public var canRecord: Bool {
        guard needsReceivedAmount else {
            return true
        }
        guard case .success = readAmount(), case .success = readReceived() else {
            return false
        }
        return true
    }

    /// The amount received, or `nil` with `receivedError` set: above zero, in To's decimals, as on the form.
    func parseReceived() -> Decimal? {
        switch readReceived() {
        case .success(let received):
            return received
        case .failure(let problem):
            receivedError = problem.message
            return nil
        }
    }

    /// Received read in To's currency: above zero and in To's decimals, or the message saying why not. It sets
    /// nothing, so `canRecord` and the hint can read it as the text changes.
    func readReceived() -> Result<Decimal, ScheduledPayInputProblem> {
        guard let code = receivedCurrencyCode else {
            return .failure(ScheduledPayInputProblem(message: ScheduledText.enterAmount))
        }
        let received: Decimal
        do {
            received = try AmountInput.parse(receivedText, currencyCode: code, locale: locale)
        } catch .tooManyDecimals(let allowed) {
            return .failure(
                ScheduledPayInputProblem(message: ScheduledText.tooManyDecimals(allowed, currencyCode: code))
            )
        } catch {
            let example = MoneyFormatter(locale: locale).exampleAmount(currencyCode: code)
            return .failure(ScheduledPayInputProblem(message: ScheduledText.enterAmountLike(example)))
        }
        guard received > 0 else {
            return .failure(ScheduledPayInputProblem(message: ScheduledText.enterReceived(code)))
        }
        return .success(received)
    }
}

/// Why an amount on the Pay sheet can't be recorded: the message shown under its field.
struct ScheduledPayInputProblem: Error, Equatable {
    let message: String
}
