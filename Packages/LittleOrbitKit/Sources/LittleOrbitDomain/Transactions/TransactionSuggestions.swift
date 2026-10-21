import Foundation

/// An autocomplete suggestion for the description or payee field.
public struct TransactionSuggestion: Equatable, Sendable, Identifiable {
    public var text: String
    public var useCount: Int
    public var lastUsed: Date?
    public var payeeID: UUID?
    /// For payees: the category last used with them, preselected when the payee is picked.
    public var categoryID: UUID?

    public var id: String { payeeID?.uuidString ?? text }
}

/// Autocomplete from earlier descriptions and payees (AC, S38). Matching ignores case and accents, and looks
/// at the start of the text or of any word. An exact match isn't offered, since it's already typed.
public enum TransactionSuggestions {
    public static let defaultLimit = 5

    public static func descriptions(
        matching query: String,
        in transactions: [Transaction],
        limit: Int = defaultLimit,
    ) -> [TransactionSuggestion] {
        let key = fold(query)
        guard !key.isEmpty else {
            return []
        }
        var byKey: [String: TransactionSuggestion] = [:]
        for transaction in transactions where transaction.deletedAt == nil {
            guard let details = LedgerText.trimmedOptional(transaction.details) else {
                continue
            }
            let folded = fold(details)
            guard folded != key, matches(folded, key) else {
                continue
            }
            var suggestion = byKey[folded] ?? TransactionSuggestion(text: details, useCount: 0)
            suggestion.useCount += 1
            if suggestion.lastUsed.map({ transaction.date > $0 }) ?? true {
                suggestion.lastUsed = transaction.date
                suggestion.text = details
            }
            byKey[folded] = suggestion
        }
        return ranked(Array(byKey.values), limit: limit)
    }

    public static func payees(
        matching query: String,
        payees: [Payee],
        transactions: [Transaction],
        limit: Int = defaultLimit,
    ) -> [TransactionSuggestion] {
        let key = fold(query)
        guard !key.isEmpty else {
            return []
        }
        var counts: [UUID: Int] = [:]
        for transaction in transactions where transaction.deletedAt == nil {
            if let payeeID = transaction.payeeID {
                counts[payeeID, default: 0] += 1
            }
        }
        let found = payees.compactMap { payee -> TransactionSuggestion? in
            let folded = fold(payee.name)
            guard payee.deletedAt == nil, !payee.isArchived, folded != key, matches(folded, key) else {
                return nil
            }
            return TransactionSuggestion(
                text: payee.name,
                useCount: counts[payee.id] ?? 0,
                lastUsed: payee.lastUsedAt,
                payeeID: payee.id,
                categoryID: payee.defaultCategoryID,
            )
        }
        return ranked(found, limit: limit)
    }

    private static func ranked(_ items: [TransactionSuggestion], limit: Int) -> [TransactionSuggestion] {
        Array(
            items.sorted { lhs, rhs in
                if lhs.useCount != rhs.useCount {
                    return lhs.useCount > rhs.useCount
                }
                let left = lhs.lastUsed ?? .distantPast
                let right = rhs.lastUsed ?? .distantPast
                if left != right {
                    return left > right
                }
                return lhs.text < rhs.text
            }
            .prefix(limit)
        )
    }

    private static func fold(_ text: String) -> String {
        LedgerText.trimmed(text).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func matches(_ candidate: String, _ key: String) -> Bool {
        if candidate.hasPrefix(key) {
            return true
        }
        return candidate.split(separator: " ").contains { $0.hasPrefix(key) }
    }
}
