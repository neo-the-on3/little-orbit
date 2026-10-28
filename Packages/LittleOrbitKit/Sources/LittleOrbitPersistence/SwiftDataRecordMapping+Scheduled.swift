#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData

    /// A scheduled item's occurrence records (#26), with an occurrence's own values (D45). Kept beside
    /// `SwiftDataRecordMapping.swift`, which maps the item.
    extension LittleOrbitSchemaV1.ScheduledOccurrenceRecord: IdentifiedLedgerRecord {
        var recordID: UUID { id }
        func apply(_ occurrence: ScheduledOccurrence) throws {
            id = occurrence.id
            year = occurrence.day.year
            month = occurrence.day.month
            dayOfMonth = occurrence.day.day
            outcome = occurrence.outcome.rawValue
            transactionID = occurrence.transactionID
            recordedAutomatically = occurrence.recordedAutomatically
            try apply(occurrence.edit)
            createdAt = occurrence.createdAt
            updatedAt = occurrence.updatedAt
            deletedAt = occurrence.deletedAt
        }

        func makeOccurrence() -> ScheduledOccurrence {
            ScheduledOccurrence(
                id: id,
                day: CalendarDay(year: year, month: month, day: dayOfMonth),
                // An unknown outcome reads as posted, so the occurrence is never recorded twice.
                outcome: ScheduledOutcome(rawValue: outcome) ?? .posted,
                transactionID: transactionID,
                recordedAutomatically: recordedAutomatically,
                edit: makeEdit(),
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
            )
        }

        private func apply(_ edit: ScheduledOccurrenceEdit?) throws {
            editFields = edit.map { $0.fields.map(\.rawValue).joined(separator: ",") }
            editYear = edit?.day?.year
            editMonth = edit?.day?.month
            editDayOfMonth = edit?.day?.day
            // Kept with the decimal places it has, so it reads back exactly, whatever the account's currency.
            let amount = try edit?.amount
                .map { try MinorUnitDecimal.store($0, scale: MinorUnitDecimal.fractionalDigits(in: $0)) }
            editAmountMinor = amount?.minorUnits
            editAmountScale = amount?.scale
            editAccountID = edit?.accountID
            editTransferAccountID = edit?.transferAccountID
            let received = try edit?.destinationAmount
                .map { try MinorUnitDecimal.store($0, scale: MinorUnitDecimal.fractionalDigits(in: $0)) }
            editDestinationAmountMinor = received?.minorUnits
            editDestinationAmountScale = received?.scale
            editReceivedCurrencyCode = edit?.receivedCurrencyCode
            editCategoryID = edit?.categoryID
            editPayeeID = edit?.payeeID
            editDetails = edit?.details
            editNote = edit?.note
        }

        private func makeEdit() -> ScheduledOccurrenceEdit? {
            guard let editFields else {
                return nil
            }
            // An unknown field name is left out: the occurrence follows the item for it.
            let fields = editFields.split(separator: ",").compactMap { ScheduledEditField(rawValue: String($0)) }
            var day: CalendarDay?
            if let editYear, let editMonth, let editDayOfMonth {
                day = CalendarDay(year: editYear, month: editMonth, day: editDayOfMonth)
            }
            var amount: Decimal?
            if let editAmountMinor, let editAmountScale {
                amount = MinorUnitDecimal.decimal(
                    from: MinorUnitDecimal.Stored(minorUnits: editAmountMinor, scale: editAmountScale)
                )
            }
            var received: Decimal?
            if let editDestinationAmountMinor, let editDestinationAmountScale {
                received = MinorUnitDecimal.decimal(
                    from: MinorUnitDecimal.Stored(
                        minorUnits: editDestinationAmountMinor,
                        scale: editDestinationAmountScale,
                    )
                )
            }
            return ScheduledOccurrenceEdit(
                fields: fields,
                day: day,
                amount: amount,
                accountID: editAccountID,
                transferAccountID: editTransferAccountID,
                destinationAmount: received,
                receivedCurrencyCode: editReceivedCurrencyCode,
                categoryID: editCategoryID,
                payeeID: editPayeeID,
                details: editDetails,
                note: editNote,
            )
        }
    }
#endif
