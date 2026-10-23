import Foundation

/// Whether a transaction is a refund and, if so, whether its original is still there (D19, #55). Screens
/// word it: a linked refund reads 'Refund', an unlinked one 'Refund (original deleted)'.
public enum RefundStatus: Equatable, Sendable {
    case notRefund
    case linked(originalID: UUID)
    /// The original expense was deleted, or the refund came in unlinked by CSV import or sync (D35.2).
    case originalDeleted

    public init(of transaction: Transaction) {
        guard transaction.isRefund else {
            self = .notRefund
            return
        }
        if let originalID = transaction.refundOfID {
            self = .linked(originalID: originalID)
        } else {
            self = .originalDeleted
        }
    }
}
