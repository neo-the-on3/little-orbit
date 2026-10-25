import Foundation
import LittleOrbitDomain

/// The account delete confirmation's slot after its first sentence (D344, D236.2). Each case of the #23 message is
/// still one whole catalog message, with the slot in the same place every time. The slot holds standalone
/// sentences, each its own catalog entry: D288's about the account's scheduled items first (#201), then D372's
/// about occurrences moved to the account.
extension AccountDeletePrompt {
    /// The message for `impact`, with D288's sentence in the slot when the account has scheduled items, then D372's
    /// when occurrences were moved to it (D372.1).
    static func message(_ impact: AccountDeletionImpact, movedOccurrences: Int = 0) -> String {
        let scheduled = scheduledSentence(items: impact.scheduledItemCount, transfers: impact.scheduledTransferCount)
        guard let slot = slot([scheduled, movedOccurrencesSentence(movedOccurrences)]) else {
            return message(transactions: impact.transactionCount, transfers: impact.transferCount)
        }
        return message(transactions: impact.transactionCount, transfers: impact.transferCount, scheduled: slot)
    }

    /// D372: "1 scheduled occurrence moved to this account will go back to its item’s account." and its plural;
    /// `nil` for none, so the message is unchanged.
    static func movedOccurrencesSentence(_ count: Int) -> String? {
        guard count > 0 else {
            return nil
        }
        return FeatureText.plural(
            "%lld scheduled occurrences moved to this account will go back to their items’ accounts.",
            one: "%lld scheduled occurrence moved to this account will go back to its item’s account.",
            count,
        )
    }

    /// The slot's sentences in order, D288's first; `nil` when there are none.
    static func slot(_ sentences: [String?]) -> String? {
        let present = sentences.compactMap { $0 }
        guard let first = present.first else {
            return nil
        }
        return present.dropFirst().reduce(first) { FeatureText.format("%1$@ %2$@", $0, $1) }
    }
}
