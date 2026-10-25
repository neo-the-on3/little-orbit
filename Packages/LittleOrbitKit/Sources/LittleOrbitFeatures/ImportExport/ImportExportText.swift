import Foundation
import LittleOrbitDomain

/// The wording of CSV import and export (#30), from the package's String Catalog. Domain values carry no text;
/// this turns fields, issues and counts into what the screens show.
enum ImportExportText {
    // MARK: Entry points

    static var sectionTitle: String {
        FeatureText.string("Import & Export", comment: "Settings row and screen title: CSV import and export.")
    }

    /// iOS Settings › Import & Export: no ellipsis on iOS (D323.11).
    static var importRow: String {
        FeatureText.string(
            "Import CSV from Files",
            comment: "iOS Settings › Import & Export row: pick a CSV file in Files to import.",
        )
    }

    static var exportRow: String {
        FeatureText.string(
            "Export Transactions to CSV",
            comment: "iOS Settings › Import & Export row: export transactions as a CSV file.",
        )
    }

    /// Mac File menu, after Restore from Backup… (D323.9, D323.12).
    static var importMenu: String {
        FeatureText.string("Import…", comment: "Mac File menu item (⇧⌘I): pick a CSV file to import.")
    }

    static var exportMenu: String {
        FeatureText.string(
            "Export Transactions…",
            comment: "Mac File menu item (⇧⌘E): export transactions as a CSV file.",
        )
    }

    static var sectionFooter: String {
        FeatureText.string(
            "Import transactions from a bank or another app’s CSV file. Exported files open in Numbers, Excel and other apps. Files stay on this device.",
            comment: "Settings › Import & Export: the footer under the import and export rows.",
        )
    }

    // MARK: Import steps

    static var importTitle: String {
        FeatureText.string("Import CSV", comment: "CSV import sheet: the title.")
    }

    static var cancel: String {
        FeatureText.string(
            "Cancel",
            comment:
                "Category and payee sheets and alerts, the CSV import and export sheets, and the Undo Import confirmation: close without changing anything.",
        )
    }

    static var next: String {
        FeatureText.string("Next", comment: "CSV import sheet: go to the next step.")
    }

    static var back: String {
        FeatureText.string("Back", comment: "CSV import sheet: go to the previous step.")
    }

    static var done: String {
        FeatureText.string(
            "Done",
            comment:
                "Categories and Payees screens: ends reordering or selecting. Transaction form category picker: puts the checked category on the form. CSV import summary: closes the import sheet.",
        )
    }

    static var importAction: String {
        FeatureText.string("Import", comment: "CSV import Review: the toolbar button that saves the selected rows.")
    }

    static var accountStep: String {
        FeatureText.string(
            "Account",
            comment: "CSV import: the step that picks the account for a file without an Account column.",
        )
    }

    static var columnsStep: String {
        FeatureText.string("Columns", comment: "CSV import: the step where each column gets a field.")
    }

    static var matchStep: String {
        FeatureText.string(
            "Match",
            comment: "CSV import: the step where names in the file are matched to accounts, categories and payees.",
        )
    }

    static var reviewStep: String {
        FeatureText.string("Review", comment: "CSV import: the step that lists what will be imported.")
    }

    static var reading: String {
        FeatureText.string("Reading File…", comment: "CSV import: progress while the file is read or checked.")
    }

    static var importing: String {
        FeatureText.string("Importing…", comment: "CSV import: progress while the transactions are saved.")
    }

    /// “File: bank.csv · 245 rows”.
    static func fileSummary(name: String, rows: Int) -> String {
        FeatureText.format("%1$@ · %2$@", name, FeatureText.plural("%lld rows", one: "%lld row", rows))
    }

    // MARK: Columns

    static var columnsHeader: String {
        FeatureText.string("Columns in File", comment: "CSV import Columns step: the section of the file’s columns.")
    }

    static var columnsFooter: String {
        FeatureText.string(
            "Date and an amount are required. Use one signed Amount column, or separate Expense Amount and Income Amount columns.",
            comment: "CSV import Columns step: the footer under the columns.",
        )
    }

    static var formatHeader: String {
        FeatureText.string(
            "Format",
            comment: "CSV import Columns step: the section with the date format and decimal separator.",
        )
    }

    static var dateFormat: String {
        FeatureText.string("Date Format", comment: "CSV import Columns step: the date order picker’s label.")
    }

    static var decimalSeparator: String {
        FeatureText.string(
            "Decimal Separator",
            comment: "CSV import Columns step: the decimal separator picker’s label.",
        )
    }

    /// “DD/MM/YYYY · Detected”: the date format the file's dates point to.
    static func detectedFormat(_ format: String) -> String {
        FeatureText.format("%1$@ · Detected", format)
    }

    static var ambiguousDates: String {
        FeatureText.string(
            "Some dates could be read either way. Check the date format.",
            comment: "CSV import Columns step: shown when the file’s dates fit more than one date order.",
        )
    }

    static var amountRequired: String {
        FeatureText.string(
            "Choose a Date column, and an Amount column or Expense Amount and Income Amount columns.",
            comment: "CSV import Columns step: why Next is off.",
        )
    }

    static var notImported: String {
        FeatureText.string("Don’t Import", comment: "CSV import Columns step: the choice that skips a column.")
    }

    static var previewHeader: String {
        FeatureText.string(
            "Preview",
            comment: "CSV import Columns step: the section showing the first rows as they’ll be read.",
        )
    }

    /// “Row 2”.
    static func row(_ number: Int) -> String {
        FeatureText.format("Row %lld", number)
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func field(_ field: ImportField) -> String {
        switch field {
        case .date: FeatureText.string("Date", comment: "CSV import column field: the transaction date.")
        case .type:
            FeatureText.string("Type", comment: "CSV import column field: expense, income, transfer or refund.")
        case .account: FeatureText.string("Account", comment: "CSV import column field: the account.")
        case .toAccount:
            FeatureText.string("To Account", comment: "CSV import column field: a transfer’s destination account.")
        case .amount:
            FeatureText.string("Amount", comment: "CSV import column field: the amount, negative for expenses.")
        case .destinationAmount:
            FeatureText.string(
                "Destination Amount",
                comment: "CSV import column field: what a transfer between currencies receives.",
            )
        case .currency:
            FeatureText.string(
                "Currency",
                comment:
                    "CSV import column field: the currency code. Spending report: the currency picker’s label, shown only with spending in 2 or more currencies.",
            )
        case .expenseAmount:
            FeatureText.string(
                "Expense Amount",
                comment: "CSV import column field: a file’s money-out column (D323.2). Title case, as a menu item.",
            )
        case .incomeAmount:
            FeatureText.string(
                "Income Amount",
                comment: "CSV import column field: a file’s money-in column (D323.2). Title case, as a menu item.",
            )
        case .category:
            FeatureText.string(
                "Category",
                comment: "Transaction form: the category picker’s title. CSV import column field: the category.",
            )
        case .payee: FeatureText.string("Payee", comment: "CSV import column field: the payee.")
        case .description: FeatureText.string("Description", comment: "CSV import column field: the description.")
        case .notes: FeatureText.string("Notes", comment: "CSV import column field: the notes.")
        }
    }

    static func dateOrder(_ order: ImportDateOrder) -> String {
        switch order {
        case .dayMonthYear: FeatureText.string("DD/MM/YYYY", comment: "CSV import date format: day, month, year.")
        case .monthDayYear: FeatureText.string("MM/DD/YYYY", comment: "CSV import date format: month, day, year.")
        case .yearMonthDay: FeatureText.string("YYYY-MM-DD", comment: "CSV import date format: year, month, day.")
        }
    }

    static func separator(_ separator: ImportDecimalSeparator) -> String {
        switch separator {
        case .period: FeatureText.string("Period (1,234.56)", comment: "CSV import decimal separator: a period.")
        case .comma: FeatureText.string("Comma (1.234,56)", comment: "CSV import decimal separator: a comma.")
        }
    }

    // MARK: Account and Match

    static var accountQuestion: String {
        FeatureText.string(
            "Which account is this file for?",
            comment: "CSV import: the title of the step that picks the account for a file without an Account column.",
        )
    }

    static var accountFooter: String {
        FeatureText.string(
            "The file has no Account column, so every row goes to this account.",
            comment: "CSV import account step: the footer.",
        )
    }

    static var matchAccounts: String {
        FeatureText.string("Accounts", comment: "CSV import Match step: the section of account names in the file.")
    }

    static var matchCategories: String {
        FeatureText.string(
            "Categories",
            comment:
                "Settings row and screen title: the category manager. CSV import Match step: the section of category names in the file.",
        )
    }

    static var matchPayees: String {
        FeatureText.string(
            "Payees",
            comment:
                "Settings row and screen title: the payee manager. CSV import Match step: the section of payee names in the file.",
        )
    }

    static var matchFooter: String {
        FeatureText.string(
            "Names that match existing ones, ignoring case, use them. The rest are created when you import.",
            comment: "CSV import Match step: the footer.",
        )
    }

    static var createNew: String {
        FeatureText.string(
            "Create New",
            comment: "CSV import Match step: the choice that creates a new record for a name.",
        )
    }

    /// “Food › Groceries”: a subcategory with its parent.
    static func categoryPath(parent: String, name: String) -> String {
        FeatureText.format("%1$@ › %2$@", parent, name)
    }

    /// “Withdrawal: “1.250,00/-””: the column and the raw value under a row issue (D323.3, D269).
    static func issueSource(column: String, value: String) -> String {
        FeatureText.format("%1$@: “%2$@”", column, value)
    }
}
