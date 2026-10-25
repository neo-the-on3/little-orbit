#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import SwiftData

    /// A scheduled item's settled occurrences (#26). Kept beside `SwiftDataRecordMapping.swift`, which maps the item.
    extension LittleOrbitSchemaV1.ScheduledOccurrenceRecord: IdentifiedLedgerRecord {
        var recordID: UUID { id }
        func apply(_ occurrence: ScheduledOccurrence) {
            id = occurrence.id
            year = occurrence.day.year
            month = occurrence.day.month
            dayOfMonth = occurrence.day.day
            outcome = occurrence.outcome.rawValue
            transactionID = occurrence.transactionID
            recordedAutomatically = occurrence.recordedAutomatically
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
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
            )
        }
    }
#endif
