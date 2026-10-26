import Foundation
import LittleOrbitDomain

/// The Columns step's rows and date-format choices.
extension CSVImportViewModel {
    public var columnRows: [ImportColumnRow] {
        guard let file else { return [] }
        return file.table.header.indices.map { column in
            ImportColumnRow(
                id: column,
                header: file.table.header[column],
                field: mapping.field(at: column),
                samples: file.samples(column: column, limit: 3).joined(separator: ", "),
            )
        }
    }

    public var canContinueFromColumns: Bool {
        mapping.missingRequired.isEmpty
    }

    public var isDateOrderDetected: Bool {
        detection?.date.order == dateOrder
    }

    public var hasAmbiguousDates: Bool {
        detection?.date.isAmbiguous == true
    }

    /// The date orders that read the file's dates, or every order when none fits them all.
    public var dateOrderChoices: [ImportDateOrder] {
        let candidates = detection?.date.candidates ?? []
        return candidates.isEmpty ? ImportDateOrder.allCases : candidates
    }
}
