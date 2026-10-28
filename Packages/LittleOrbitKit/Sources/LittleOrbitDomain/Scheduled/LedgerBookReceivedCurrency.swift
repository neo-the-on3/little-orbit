import Foundation

extension LedgerBook {
    /// Whether a scheduled item's received amount, if it has one, can still be read as entered: its
    /// `receivedCurrencyCode` is To's current currency, and that differs from From's (#207 B1). An item with no
    /// received amount passes. One with a received amount and no code (a store or backup made before the code
    /// existed) fails, as does one whose To or From isn't in the ledger.
    public static func receivedCurrencyIsCurrent(of item: ScheduledItem, in snapshot: LedgerSnapshot) -> Bool {
        guard item.type == .transfer, item.destinationAmount != nil else {
            return true
        }
        guard let code = item.receivedCurrencyCode,
            let target = account(item.transferAccountID, in: snapshot),
            code == target.currencyCode
        else {
            return false
        }
        guard let source = account(item.accountID, in: snapshot), source.currencyCode != code else {
            return false
        }
        return true
    }

    /// Throws `receivedCurrencyMismatch` unless `receivedCurrencyIsCurrent(of:in:)`. The item's save and its
    /// posting check it before anything is written, so a refused one writes nothing.
    static func validateReceivedCurrency(of item: ScheduledItem, in snapshot: LedgerSnapshot) throws {
        guard receivedCurrencyIsCurrent(of: item, in: snapshot) else {
            throw LedgerValidationError.receivedCurrencyMismatch
        }
    }

    /// The account with `id`, deleted or not: its currency is what the received amount is checked against.
    private static func account(_ id: UUID?, in snapshot: LedgerSnapshot) -> Account? {
        id.flatMap { id in snapshot.accounts.first { $0.id == id } }
    }
}
