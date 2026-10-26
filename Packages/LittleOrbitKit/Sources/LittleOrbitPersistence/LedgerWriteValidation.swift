import Foundation
import LittleOrbitDomain

/// A new attachment arrived without its bytes (`bytesLeftOut`) and the store has none for it (#235 N2).
struct AttachmentBytesMissing: Error, Equatable {}

extension Attachment {
    /// Read without its bytes (`makeAttachmentDetails`): `data` is empty but the stored size isn't.
    var bytesLeftOut: Bool {
        data.isEmpty && byteSize > 0
    }
}

/// Everything a SwiftData write can refuse, checked before it changes a single record (#265). A write that fails
/// after it has changed records gets a new context instead of `rollback()`, which SwiftData can trap in; these
/// checks keep the refusals the ledger itself causes (an amount that can't be stored, a new attachment without
/// its bytes) out of that path. Each check uses the rule function the record mapping calls (`StoredAmount.stored`), with the same
/// currency for each value. Plain values, so it runs and is tested on every platform.
enum LedgerWriteValidation {
    /// The incremental write's values: those `changes` writes, as `snapshot` has them. `storedAttachmentIDs` are
    /// the attachments the store has, which keep their bytes when one comes without them.
    static func validate(
        _ changes: LedgerWriteSet,
        of snapshot: LedgerSnapshot,
        storedAttachmentIDs: Set<UUID>,
    ) throws {
        for attachment in changes.attachments.upserted
        where attachment.bytesLeftOut && !storedAttachmentIDs.contains(attachment.id) {
            throw AttachmentBytesMissing()
        }
        try validateAmounts(
            accounts: changes.accounts.upserted,
            transactions: changes.transactions.upserted,
            splits: changes.splits.upserted,
            limits: changes.limits.upserted,
            scheduledItems: changes.scheduledItems.upserted,
            of: snapshot,
        )
    }

    /// The whole-store write's values: every amount in `snapshot`. Its attachments' bytes are resolved first.
    static func validateWholeStore(_ snapshot: LedgerSnapshot) throws {
        try validateAmounts(
            accounts: snapshot.accounts,
            transactions: snapshot.transactions,
            splits: snapshot.splits,
            limits: LedgerWriteSet.limits(of: snapshot),
            scheduledItems: snapshot.scheduledItems,
            of: snapshot,
        )
    }

    private static func validateAmounts(
        accounts: [Account],
        transactions: [Transaction],
        splits: [TransactionSplit],
        limits: [OwnedRecord<BudgetLimit>],
        scheduledItems: [ScheduledItem],
        of snapshot: LedgerSnapshot,
    ) throws {
        let currencies = Dictionary(
            snapshot.accounts.map { ($0.id, $0.currencyCode) },
            uniquingKeysWith: { first, _ in first },
        )
        for account in accounts {
            _ = try StoredAmount.stored(account.openingBalance, currencyCode: account.currencyCode)
            if let limit = account.creditLimit {
                _ = try StoredAmount.stored(limit, currencyCode: account.currencyCode)
            }
        }
        for transaction in transactions {
            let source = transaction.accountID.flatMap { currencies[$0] } ?? CurrencyCode.fallback
            _ = try StoredAmount.stored(transaction.amount, currencyCode: source)
            if let destination = transaction.destinationAmount {
                let code = transaction.transferAccountID.flatMap { currencies[$0] } ?? source
                _ = try StoredAmount.stored(destination, currencyCode: code)
            }
        }
        try validateSplits(splits, of: snapshot, currencies: currencies)
        let budgetCurrencies = Dictionary(
            snapshot.budgets.map { ($0.id, $0.currencyCode) },
            uniquingKeysWith: { first, _ in first },
        )
        for limit in limits {
            let code = budgetCurrencies[limit.ownerID] ?? CurrencyCode.fallback
            _ = try StoredAmount.stored(limit.value.amount, currencyCode: code)
        }
        for item in scheduledItems {
            _ = try StoredAmount.stored(item.amount, currencyCode: item.accountID.flatMap { currencies[$0] })
            if let destination = item.destinationAmount {
                let code = item.transferAccountID.flatMap { currencies[$0] }
                _ = try StoredAmount.stored(destination, currencyCode: code)
            }
        }
    }

    private static func validateSplits(
        _ splits: [TransactionSplit],
        of snapshot: LedgerSnapshot,
        currencies: [UUID: String],
    ) throws {
        guard !splits.isEmpty else {
            return
        }
        let accountOfTransaction = Dictionary(
            snapshot.transactions.map { ($0.id, $0.accountID) },
            uniquingKeysWith: { first, _ in first },
        )
        for split in splits {
            let code =
                split.transactionID.flatMap { accountOfTransaction[$0] ?? nil }.flatMap { currencies[$0] }
                ?? CurrencyCode.fallback
            _ = try StoredAmount.stored(split.amount, currencyCode: code)
        }
    }
}
