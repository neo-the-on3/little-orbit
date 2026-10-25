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
}
