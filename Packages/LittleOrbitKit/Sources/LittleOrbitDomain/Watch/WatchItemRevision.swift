import Foundation

/// A fingerprint of what a watch Pay or Skip would record for a scheduled item (D374): its type, amounts,
/// accounts, category, payee, description, note and schedule. The iPhone puts it in each snapshot row and the watch
/// sends it back with Pay and Skip, so a request made against an item that was changed on the iPhone since is
/// recognised as stale and records nothing.
///
/// Settling an occurrence doesn't change it, so paying one occurrence on the iPhone never makes a watch request for
/// another one stale. Only the iPhone computes it, so it needs to be stable on one device, not across builds of the
/// encoder; a change after an update only makes an in-flight request stale, which records nothing.
public enum WatchItemRevision {
    public static func of(_ item: ScheduledItem) -> UInt32 {
        let fields = Fields(
            type: item.type,
            amount: item.amount,
            destinationAmount: item.destinationAmount,
            accountID: item.accountID,
            transferAccountID: item.transferAccountID,
            categoryID: item.categoryID,
            payeeID: item.payeeID,
            details: item.details,
            note: item.note,
            startDay: item.startDay,
            repeatRule: item.repeatRule,
            endDay: item.endDay,
            timeZoneID: item.timeZoneID,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(fields) else {
            return 0
        }
        // FNV-1a, 32 bits: small enough for the snapshot's JSON, and the same on every run.
        var hash: UInt32 = 2_166_136_261
        for byte in data {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return hash
    }

    private struct Fields: Encodable {
        var type: TransactionType
        var amount: Decimal
        var destinationAmount: Decimal?
        var accountID: UUID?
        var transferAccountID: UUID?
        var categoryID: UUID?
        var payeeID: UUID?
        var details: String?
        var note: String?
        var startDay: CalendarDay
        var repeatRule: ScheduleRepeat
        var endDay: CalendarDay?
        var timeZoneID: String
    }
}
