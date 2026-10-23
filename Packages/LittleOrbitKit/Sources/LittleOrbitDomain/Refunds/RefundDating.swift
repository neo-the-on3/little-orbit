import Foundation

/// When an expense counts as dated after one of its refunds: the one comparison for D224.2's stale reason on
/// Undo (`RefundRestoreCheck`) and, later, D112's save check in #34, so the two can't disagree.
///
/// Each record is read on its own calendar day in its own stored time zone, also when the two were entered in
/// different zones; times and the device's zone play no part (D229.1, D35.4). The same day is fine (D112: "on
/// or after the original's date").
public enum RefundDating {
    public static func isOriginal(_ original: Transaction, datedAfter refund: Transaction) -> Bool {
        TransactionTiming.day(of: original) > TransactionTiming.day(of: refund)
    }
}
