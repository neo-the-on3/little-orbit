import Foundation
import LittleOrbitDomain

/// One account's totals on the Review step (#60).
public struct ImportAccountTotalRow: Identifiable, Equatable, Sendable {
    public let id: ImportRef
    public let name: String
    public let currencyCode: String
    public let income: String
    public let expense: String
}

/// Review's Will Be Created counts and Totals by Account for the current ticks (#60).
struct ImportReviewTotals: Equatable, Sendable {
    var created = ImportCreatedCounts()
    var accounts: [ImportAccountTotalRow] = []
}

/// What the sheet does differently for a Debit & Credit export (#60).
extension CSVImportViewModel {
    /// Whether the file is a Debit & Credit export (#60, D44): its own columns, dates, amounts and wording.
    public var isDebitAndCredit: Bool {
        file?.formatID == DebitAndCreditFormat.formatID
    }

    /// The note on the Columns step when a preset was applied, or `nil`.
    public var formatNote: String? {
        isDebitAndCredit ? ImportExportText.debitAndCreditDetected : nil
    }

    /// Whether the Columns step offers the date format and decimal separator. A Debit & Credit file has a
    /// fixed layout, so it doesn't.
    public var showsReadFormat: Bool {
        !isDebitAndCredit
    }

    /// The region's currency first, then every other circulating one (#60 design default 4).
    public var currencyOptions: [String] {
        [defaultCurrency] + CurrencyCode.circulatingCodes.filter { $0 != defaultCurrency }
    }

    /// Sets the currency of an account the import creates (#60). The preview is planned again, so transfer
    /// halves pair or don't by the new currency (D330) and decimals the currency doesn't have become row issues.
    public func setCurrency(_ code: String, forNewAccount key: ImportMatchKey) async {
        guard case .account = key.kind else { return }
        choices.newAccountCurrencies[key.nameKey] = code
        await plan()
    }

    /// “INR — Indian Rupee”, the account form's format (D329).
    public func currencyTitle(for code: String) -> String {
        CurrencyTitle.title(for: code, locale: locale)
    }
}
