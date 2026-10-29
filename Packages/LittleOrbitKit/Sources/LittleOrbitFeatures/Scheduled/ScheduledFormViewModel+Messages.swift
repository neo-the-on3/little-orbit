import Foundation
import LittleOrbitDomain

/// The Scheduled form's names and field messages.
extension ScheduledFormViewModel {
    /// The edited item's short name, as the Delete confirmation names it.
    var itemName: String {
        original.map { ScheduledPresenter(listing: listing, locale: locale).shortName(of: $0) } ?? ""
    }

    /// The account form's messages (D334.12).
    func message(_ error: AmountInputError) -> String {
        switch error {
        case .tooManyDecimals(let allowed):
            ScheduledText.tooManyDecimals(allowed, currencyCode: currencyCode)
        case .negative, .outOfRange, .notANumber:
            ScheduledText.enterAmountLike(MoneyFormatter(locale: locale).exampleAmount(currencyCode: currencyCode))
        }
    }

    /// A refused Save: nothing was saved, and the form stays open with its edits unless the item is gone.
    func showSaveFailure(_ error: any Error) {
        switch error as? LedgerValidationError {
        case .scheduleEndsBeforeStart:
            formError = ScheduledText.endBeforeStart
        case .receivedCurrencyMismatch:
            // To's currency changed since the form read it: the stale-step message "‹To› has changed since then.
            // Nothing was changed." (#207 B1).
            alert = ScheduledText.toChangedNothingSaved(listing.account(transferAccountID)?.name)
        case .fromCurrencyMismatch(let mismatch):
            // From can't pay an occurrence the save leaves: name From and both currencies (#202 B2).
            alert = cantPayAlert(mismatch)
        case .missingScheduledItem where !isNew:
            // Deleted elsewhere while the form was open: OK closes the form (#258).
            alert = ScheduledText.deletedNothingSaved(itemName)
            alertClosesForm = true
        case .occurrenceDayTaken(let day):
            // “Can’t Move to 1 Sep”: the user picks another day (D381.1).
            let date = ScheduledPresenter.date(day, today: today, locale: locale)
            alert = ScheduledText.cantMove(itemName, to: date)
        case .occurrenceSettledSinceOpened:
            // Paid or skipped in another window since the form opened (D381.2).
            alert = ScheduledText.changedNothingSaved(itemName)
        default:
            alert = saveFailedAlert(error)
        }
    }

    private func cantPayAlert(_ mismatch: ScheduledCurrencyMismatch) -> CategoryAlert {
        let name = listing.account(mismatch.accountID)?.name ?? StaleText.theAccount
        return ScheduledText.cantPayInCurrency(name, mismatch, locale: locale)
    }
}
