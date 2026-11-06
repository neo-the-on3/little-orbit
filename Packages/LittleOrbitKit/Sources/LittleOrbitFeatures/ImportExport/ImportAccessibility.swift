import Foundation
import LittleOrbitDomain

extension ImportColumnRow {
    /// Keep the source header as the label; speak the selected mapping as the value.
    var accessibilityValue: String {
        field.map(ImportExportText.field) ?? ImportExportText.notImported
    }
}

extension ImportMatchRow {
    var accessibilityCurrencyLabel: String {
        FeatureText.format("Currency for %@", name)
    }

    /// The selected record’s name, not the source name, which remains the picker label.
    var accessibilityValue: String {
        switch choice {
        case .new: ImportExportText.createNew
        case .existing(let id): options.first { $0.id == id }?.name ?? ""
        }
    }
}

/// A count’s visible title and its separately localised, whole spoken phrase (I17).
struct ImportReviewCount: Identifiable {
    enum Kind: Hashable {
        case toImport, cantImport, shortened, alreadyImported, possibleDuplicates
        case accounts, categories, payees
    }

    let kind: Kind
    let count: Int
    var id: Kind { kind }

    var title: String {
        switch kind {
        case .toImport: ImportExportText.toImport
        case .cantImport: ImportExportText.cantImport
        case .shortened: ImportExportText.shortened
        case .alreadyImported: ImportExportText.alreadyImported
        case .possibleDuplicates: ImportExportText.possibleDuplicates
        case .accounts: ImportExportText.newAccounts
        case .categories: ImportExportText.newCategories
        case .payees: ImportExportText.newPayees
        }
    }

    var spoken: String {
        switch kind {
        case .toImport: FeatureText.plural("%lld to import", one: "%lld to import", count)
        case .cantImport: FeatureText.plural("%lld can’t be imported", one: "%lld can’t be imported", count)
        case .shortened: FeatureText.plural("%lld shortened", one: "%lld shortened", count)
        case .alreadyImported: FeatureText.plural("%lld already imported", one: "%lld already imported", count)
        case .possibleDuplicates: FeatureText.plural("%lld possible duplicates", one: "%lld possible duplicate", count)
        case .accounts: ImportExportText.createdAccounts(count)
        case .categories: ImportExportText.createdCategories(count)
        case .payees: ImportExportText.createdPayees(count)
        }
    }
}

extension CSVImportViewModel {
    var accessibilityReviewCounts: [ImportReviewCount] {
        [
            ImportReviewCount(kind: .toImport, count: readyCount),
            ImportReviewCount(kind: .cantImport, count: failedCount),
            ImportReviewCount(kind: .shortened, count: shortenedCount),
            ImportReviewCount(kind: .alreadyImported, count: alreadyImportedCount),
            ImportReviewCount(kind: .possibleDuplicates, count: possibleDuplicateCount),
        ]
    }
}
