import Foundation

extension LedgerBook {
    /// The transaction one occurrence records: the item's fields, dated at noon on `postedOn` in the item's zone,
    /// with the stable ID for the item and occurrence (`ScheduledKey`).
    public static func scheduledTransaction(
        for item: ScheduledItem,
        occurrence day: CalendarDay,
        postedOn: CalendarDay,
        now: Date,
    ) throws -> Transaction {
        guard let date = TransactionCalendar.noon(on: postedOn, timeZoneID: item.timeZoneID),
            let occurrenceDate = TransactionCalendar.noon(on: day, timeZoneID: item.timeZoneID)
        else {
            throw LedgerValidationError.invalidTimeZone
        }
        return Transaction(
            id: ScheduledKey.transactionID(item: item.id, day: day),
            type: item.type,
            amount: item.amount,
            date: date,
            timeZoneID: item.timeZoneID,
            accountID: item.accountID,
            categoryID: item.type == .transfer ? nil : item.categoryID,
            payeeID: item.type == .transfer ? nil : item.payeeID,
            details: item.details,
            note: item.note,
            transferAccountID: item.type == .transfer ? item.transferAccountID : nil,
            destinationAmount: item.type == .transfer ? item.destinationAmount : nil,
            scheduledTemplateID: item.id,
            scheduledOccurrenceDate: occurrenceDate,
            createdAt: now,
        )
    }
}
