import Foundation
import LittleOrbitDomain

/// Why a row can't be imported, and the export sheet.
extension ImportExportText {
    // MARK: Row issues

    /// “Row 12: Date can’t be read as DD/MM/YYYY”.
    static func rowIssue(_ number: Int, _ message: String) -> String {
        FeatureText.format("Row %1$lld: %2$@", number, message)
    }

    // A short phrase with no full stop (D323.3, D323.15). `dateOrder` names the format an unreadable date was
    // read with.
    // swiftlint:disable:next cyclomatic_complexity
    static func issue(_ issue: ImportRowIssue, dateOrder: ImportDateOrder) -> String {
        switch issue {
        case .missingColumns:
            FeatureText.string("Row has fewer columns than the header", comment: "CSV import row issue (D323.15).")
        case .unclosedQuote:
            FeatureText.string("A quoted value isn’t closed", comment: "CSV import row issue.")
        case .missingDate:
            FeatureText.string("Date is empty", comment: "CSV import row issue (D323.15).")
        case .unreadableDate:
            FeatureText.format("Date can’t be read as %@", Self.dateOrder(dateOrder))
        case .unknownType:
            FeatureText.string(
                "Type must be Expense, Income, Transfer or Refund",
                comment: "CSV import row issue (D323.3). The Type values are the file’s own and stay in English.",
            )
        case .missingAccount:
            FeatureText.string("Account is empty", comment: "CSV import row issue (D323.15).")
        case .missingToAccount:
            FeatureText.string("Transfer has no To Account", comment: "CSV import row issue.")
        case .sameTransferAccount:
            FeatureText.string("To Account must differ from Account", comment: "CSV import row issue (D50, D108).")
        case .missingAmount:
            FeatureText.string("Amount is empty", comment: "CSV import row issue (D323.15).")
        case .unreadableAmount:
            FeatureText.string("Amount can’t be read", comment: "CSV import row issue (D323.3).")
        case .zeroAmount:
            FeatureText.string("Amount is zero", comment: "CSV import row issue.")
        case .conflictingAmounts:
            FeatureText.string(
                "Both Expense Amount and Income Amount are filled in",
                comment: "CSV import row issue (D323.3): a row has an amount in both columns.",
            )
        case .tooManyDecimalPlaces(let code):
            FeatureText.format("Too many decimal places for %@", code)
        case .unreadableDestinationAmount:
            FeatureText.string("Destination Amount can’t be read", comment: "CSV import row issue (D323.3).")
        case .destinationAmountRequired:
            FeatureText.string(
                "Destination Amount is required when the currencies differ",
                comment: "CSV import row issue (D29).",
            )
        case .destinationAmountMismatch:
            FeatureText.string(
                "Destination Amount must equal Amount for same-currency transfers",
                comment: "CSV import row issue (D29).",
            )
        case .unknownCurrency:
            FeatureText.string("Currency can’t be read", comment: "CSV import row issue (D323.3).")
        case .currencyMismatch(let accountCurrency):
            FeatureText.format("Currency differs from the account’s %@", accountCurrency)
        case .nameTooLong(let field):
            nameTooLong(field)
        }
    }

    /// A name over the limit, as one whole phrase per column (D323.3: “Any other field with a limit gets its
    /// own whole phrase”).
    private static func nameTooLong(_ field: ImportField) -> String {
        let limit = ImportText.nameLimit.formatted()
        return switch field {
        case .account:
            FeatureText.string(
                "Account is over \(limit) characters",
                comment: "CSV import row issue: the account name is too long. The number is the limit.",
            )
        case .toAccount:
            FeatureText.string(
                "To Account is over \(limit) characters",
                comment: "CSV import row issue: the transfer’s To Account name is too long. The number is the limit.",
            )
        case .payee:
            FeatureText.string(
                "Payee is over \(limit) characters",
                comment: "CSV import row issue: the payee name is too long. The number is the limit.",
            )
        default:
            FeatureText.string(
                "Category is over \(limit) characters",
                comment: "CSV import row issue: the category name is too long. The number is the limit.",
            )
        }
    }

    // MARK: Export

    static var exportTitle: String {
        FeatureText.string("Export CSV", comment: "CSV export sheet: the title.")
    }

    static var export: String {
        FeatureText.string(
            "Export",
            comment:
                "The iOS Export sheet’s confirm button (backups, and the CSV export sheet); the share sheet or save panel follows directly, so no ellipsis.",
        )
    }

    /// The Mac export sheet’s button: a save panel follows (D190, D323.13).
    static var exportEllipsis: String {
        FeatureText.string(
            "Export…",
            comment:
                "Button that opens the Export sheet on a backup (macOS, and the iOS backup detail). Mac CSV export sheet: the button that opens the save panel.",
        )
    }

    static var transactions: String {
        FeatureText.string("Transactions", comment: "CSV export: the section choosing which transactions.")
    }

    static var allTransactions: String {
        FeatureText.string(
            "All Transactions",
            comment:
                "macOS sidebar item and its screen title: every transaction, with the toolbar search. CSV export: every account.",
        )
    }

    static var someAccounts: String {
        FeatureText.string("Accounts", comment: "CSV export: only the chosen accounts.")
    }

    static var dateRange: String {
        FeatureText.string("Date Range", comment: "CSV export: the date range picker’s label.")
    }

    static var allTime: String {
        FeatureText.string("All Time", comment: "CSV export date range: everything.")
    }

    static var thisMonth: String {
        FeatureText.string(
            "This Month",
            comment: "Spending report period preset and CSV export date range: the current calendar month.",
        )
    }

    static var custom: String {
        FeatureText.string("Custom", comment: "CSV export date range: chosen start and end dates.")
    }

    static var from: String {
        FeatureText.string("From", comment: "CSV export custom range: the first day.")
    }

    static var through: String {
        FeatureText.string("To", comment: "CSV export custom range: the last day, included.")
    }

    static var isoDates: String {
        FeatureText.string(
            "ISO 8601 Dates",
            comment: "CSV export: write dates as 2026-10-20 14:30:00 instead of the short date.",
        )
    }

    static var formatFooter: String {
        FeatureText.string(
            "Comma-separated, UTF-8 with BOM. Columns: Date, Type, Account, To Account, Amount, Destination Amount, Currency, Category, Payee, Description, Notes. Expenses are negative.",
            comment:
                "CSV export: the footer describing the file. The column names are the file’s own and stay in English.",
        )
    }

    /// “Will export 1,204 transactions”.
    static func willExport(_ count: Int) -> String {
        FeatureText.plural("Will export %lld transactions", one: "Will export %lld transaction", count)
    }

    static var nothingToExport: String {
        FeatureText.string("No transactions match.", comment: "CSV export: nothing in the chosen accounts and dates.")
    }

    static var exportFailedTitle: String {
        FeatureText.string(
            "Couldn’t Export",
            comment: "CSV export: alert title when the file couldn’t be made or saved.",
        )
    }

    static var exportFailedMessage: String {
        FeatureText.string(
            "The CSV file couldn’t be created. Try again.",
            comment: "CSV export: making or saving the file failed.",
        )
    }
}
