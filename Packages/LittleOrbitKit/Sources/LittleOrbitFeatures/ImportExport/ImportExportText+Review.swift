import Foundation
import LittleOrbitDomain

/// The Review and summary steps, Undo Import and the import alerts.
extension ImportExportText {
    // MARK: Review

    /// Counts and row labels are in sentence case; section titles in title case (D323.4, D42).
    static var toImport: String {
        FeatureText.string("To import", comment: "CSV import Review: the count of rows that will be imported.")
    }

    static var toImportSection: String {
        FeatureText.string("To Import", comment: "CSV import Review: the section of rows that will be imported.")
    }

    static var cantImport: String {
        FeatureText.string(
            "Can’t import",
            comment:
                "CSV import Review and summary: the count of rows whose content keeps them from being imported (D323.17).",
        )
    }

    static var cantImportSection: String {
        FeatureText.string(
            "Can’t Import",
            comment: "CSV import Review: the section of rows that can’t be imported.",
        )
    }

    static var shortened: String {
        FeatureText.string(
            "Shortened",
            comment: "CSV import Review: the count of rows whose description or notes were shortened to fit.",
        )
    }

    static var alreadyImported: String {
        FeatureText.string(
            "Already imported",
            comment:
                "CSV import Review and summary: the count of rows identical to an existing transaction, and such a row’s label.",
        )
    }

    static var possibleDuplicates: String {
        FeatureText.string(
            "Possible duplicates",
            comment: "CSV import Review and summary: the count of rows close to an existing transaction.",
        )
    }

    static var possibleDuplicate: String {
        FeatureText.string(
            "Possible duplicate",
            comment: "CSV import Review: the label of a row close to an existing transaction.",
        )
    }

    static var notSelected: String {
        FeatureText.string(
            "Not Selected",
            comment: "CSV import Review: the section of rows that aren’t ticked, such as duplicates.",
        )
    }

    static var notSelectedCount: String {
        FeatureText.string(
            "Not selected",
            comment:
                "CSV import summary: the count of rows that could be imported but weren’t ticked (D327.4). Sentence case, like the other counts.",
        )
    }

    /// D327.1: inline at the top of the current step after the preview re-planned. Not an alert.
    static var dataChanged: String {
        FeatureText.string(
            "Your data changed, so this preview was updated.",
            comment:
                "CSV import: an inline note at the top of the current step, and a VoiceOver announcement, when accounts, categories, payees or transactions changed while the import sheet was open and the preview was planned again (D327.1).",
        )
    }

    static var notSelectedFooter: String {
        FeatureText.string(
            "Already imported means an exact match. Possible duplicate means the same account, type and amount within 3 days, with a matching payee or description. Both start unticked; tick a row to import it anyway.",
            comment: "CSV import Review: the footer under the Not Selected section.",
        )
    }

    static var nothingSaved: String {
        FeatureText.string(
            "Nothing is saved until you tap Import.",
            comment: "CSV import Review: the note under the Import button.",
        )
    }

    /// D105, D323.3, D323.16: the warning names the field that was cut. The number is the limit.
    static func warning(_ warning: ImportRowWarning) -> String {
        switch warning {
        case .descriptionShortened:
            let limit = DescriptionLimit.limit.formatted()
            return FeatureText.string(
                "Description shortened to \(limit) characters",
                comment:
                    "CSV import Review: a row whose description was cut to the limit (D105). The number is the limit.",
            )
        case .notesShortened:
            let limit = ImportText.noteLimit.formatted()
            return FeatureText.string(
                "Notes shortened to \(limit) characters",
                comment:
                    "CSV import Review: a row whose notes were cut to the limit (D323.16). The number is the limit.",
            )
        }
    }

    /// “Import 241 Transactions”.
    static func importButton(_ count: Int) -> String {
        FeatureText.plural("Import %lld Transactions", one: "Import %lld Transaction", count)
    }

    // MARK: Summary

    static var importComplete: String {
        FeatureText.string("Import Complete", comment: "CSV import Summary: the title.")
    }

    /// “241 transactions imported”.
    static func imported(_ count: Int) -> String {
        FeatureText.plural("%lld transactions imported", one: "%lld transaction imported", count)
    }

    static var alsoCreated: String {
        FeatureText.string(
            "Also Created",
            comment: "CSV import Summary: the section of accounts, categories and payees the import created.",
        )
    }

    static func createdAccounts(_ count: Int) -> String {
        FeatureText.plural("%lld new accounts", one: "%lld new account", count)
    }

    static func createdCategories(_ count: Int) -> String {
        FeatureText.plural("%lld new categories", one: "%lld new category", count)
    }

    static func createdPayees(_ count: Int) -> String {
        FeatureText.plural("%lld new payees", one: "%lld new payee", count)
    }

    static var rowsNotImported: String {
        FeatureText.string(
            "Rows Not Imported",
            comment: "CSV import Summary: the section of rows that weren’t imported.",
        )
    }

    /// D323.5: imported refunds have no link to their expense.
    static func unlinkedRefunds(_ count: Int) -> String {
        FeatureText.plural(
            "%lld refunds were imported without links to their expenses. They show as “Refund (original deleted)”.",
            one: "%lld refund was imported without a link to its expense. It shows as “Refund (original deleted)”.",
            count,
        )
    }

    /// iOS: Undo Import. The Mac adds an ellipsis because it asks first (D281, D323.8).
    static var undoImport: String {
        FeatureText.string(
            "Undo Import",
            comment: "iOS CSV import summary: the button that asks, then removes everything just imported.",
        )
    }

    static var undoImportEllipsis: String {
        FeatureText.string(
            "Undo Import…",
            comment: "Mac CSV import summary: the button that asks, then removes everything just imported (D281).",
        )
    }

    static var undoFooter: String {
        FeatureText.string(
            "Undo removes the whole batch: these transactions and anything this import created. Balances go back to what they were. You can undo this import until you close this summary.",
            comment: "CSV import summary: the footer under Undo Import (D323.8, D323.18).",
        )
    }

    /// D281: “Remove 241 Imported Transactions?”.
    static func undoTitle(_ count: Int) -> String {
        FeatureText.plural("Remove %lld Imported Transactions?", one: "Remove %lld Imported Transaction?", count)
    }

    /// D281 and D323.8: “Everything this import added from “bank.csv” is removed.”, then “That includes …”
    /// when the import created anything, then “Nothing else changes.” Each sentence is its own entry. D281’s
    /// “Import rules are kept.” waits for import rules (#37).
    static func undoMessage(fileName: String, created: [String], locale: Locale) -> String {
        let removed = FeatureText.format("Everything this import added from “%@” is removed.", fileName)
        let rest = FeatureText.string(
            "Nothing else changes.",
            comment: "Undo Import confirmation: the message’s last sentence (D281, D323.8).",
        )
        guard !created.isEmpty else {
            return sentences(removed, rest)
        }
        let list = created.formatted(.list(type: .and).locale(locale))
        let includes = FeatureText.format("That includes %@.", list)
        return sentences(sentences(removed, includes), rest)
    }

    private static func sentences(_ first: String, _ second: String) -> String {
        FeatureText.format("%1$@ %2$@", first, second)
    }

    /// D281: “the new account “Travel Card””, for exactly one created account.
    static func createdAccount(named name: String) -> String {
        FeatureText.format("the new account “%@”", name)
    }

    static var remove: String {
        FeatureText.string("Remove", comment: "CSV import Undo Import confirmation: the destructive button.")
    }

    static var undoneTitle: String {
        FeatureText.string("Import Undone", comment: "CSV import Summary after Undo Import: the title.")
    }

    // MARK: Alerts

    // D323.7: titles in title case name the file; messages end “Nothing was imported.” where that’s true.

    /// The picked file isn't a CSV file.
    static func notCSVTitle(_ fileName: String) -> String {
        FeatureText.format("Can’t Import “%@”", fileName)
    }

    static var notCSV: String {
        FeatureText.string(
            "This isn’t a CSV file. In a spreadsheet app, export it as CSV, then import that file. Nothing was imported.",
            comment: "CSV import: the picked file is a spreadsheet, PDF or other file that isn’t CSV text (D323.7).",
        )
    }

    /// A 0-byte file (D268.1).
    static func emptyFileTitle(_ fileName: String) -> String {
        FeatureText.format("Can’t Read “%@”", fileName)
    }

    static var emptyFile: String {
        FeatureText.string(
            "The file is empty. Nothing was imported.",
            comment: "CSV import: the picked file has no bytes, or only blank lines (D323.7).",
        )
    }

    /// A file with a header and no rows (D268.7).
    static var noTransactionsTitle: String {
        FeatureText.string(
            "No Transactions Found in This File",
            comment: "CSV import: alert title when the picked file has only a header row (D323.7).",
        )
    }

    static var nothingImported: String {
        FeatureText.string(
            "Nothing was imported.",
            comment: "CSV import: the message when the picked file has only a header row (D323.7).",
        )
    }

    /// Reading the file, or the current accounts, failed (D268.6).
    static func couldntOpenTitle(_ fileName: String) -> String {
        FeatureText.format("Couldn’t Open “%@”", fileName)
    }

    static var unreadable: String {
        FeatureText.string(
            "little-orbit couldn’t read this file. Try again. Nothing was imported.",
            comment: "CSV import: reading the picked file failed (D323.7). “little-orbit” is the app’s name.",
        )
    }

    static var importFailedTitle: String {
        FeatureText.string("Couldn’t Import", comment: "CSV import: alert title when saving the import failed.")
    }

    static var importFailedMessage: String {
        FeatureText.string(
            "Nothing was imported. Try again.",
            comment: "CSV import: saving failed and nothing changed.",
        )
    }

    static var loadFailedMessage: String {
        FeatureText.string(
            "Your accounts couldn’t be read. Try again.",
            comment: "CSV import: reading the current accounts, categories and payees failed.",
        )
    }

    /// Undo Import refused: something changed since (D201).
    static var undoRefusedTitle: String {
        FeatureText.string(
            "Can’t Undo Import",
            comment: "CSV import: alert title when Undo Import is refused because something changed since.",
        )
    }

    /// Undo Import failed (D201.2, D323.7).
    static var undoFailedTitle: String {
        FeatureText.string(
            "Couldn’t Undo Import",
            comment: "CSV import: alert title when Undo Import failed and nothing was removed.",
        )
    }

    static var undoChangedMessage: String {
        FeatureText.string(
            "Some imported transactions have changed since, so nothing was removed.",
            comment: "CSV import: Undo Import refused because an imported transaction was edited or deleted.",
        )
    }

    static var undoFailedMessage: String {
        FeatureText.string(
            "Nothing was removed. Try again.",
            comment: "CSV import: Undo Import failed and nothing changed.",
        )
    }

    static var okay: String {
        FeatureText.string("OK", comment: "Closes a category or payee alert, or a CSV import or export alert.")
    }
}
