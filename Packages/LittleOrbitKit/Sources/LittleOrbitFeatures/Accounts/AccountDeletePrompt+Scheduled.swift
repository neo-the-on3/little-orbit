import Foundation
import LittleOrbitDomain

/// The account delete confirmation when the account has scheduled items (D288): the #23 message with one sentence
/// after the first saying they're deleted too. Each case is still one whole catalog message (D236.2), with the
/// scheduled sentence in its slot after the first sentence.
extension AccountDeletePrompt {
    /// "Its scheduled item is deleted." and its siblings; `nil` with no scheduled items, so the message is unchanged.
    static func scheduledSentence(items count: Int, transfers: Int) -> String? {
        if count <= 0 {
            return nil
        }
        if count == 1 {
            return transfers > 0
                ? FeatureText.string(
                    "Its scheduled item, a transfer to or from another account, is deleted.",
                    comment:
                        "Account delete confirmation, after the first sentence: the account’s only scheduled item is a transfer (D288).",
                )
                : FeatureText.string(
                    "Its scheduled item is deleted.",
                    comment:
                        "Account delete confirmation, after the first sentence: the account has one scheduled item (D288).",
                )
        }
        if transfers <= 0 {
            return FeatureText.plural(
                "Its %lld scheduled items are deleted.",
                one: "Its %lld scheduled item is deleted.",
                count,
            )
        }
        return FeatureText.pluralFormat(
            "Its %1$lld scheduled items are deleted, including %2$lld transfers to or from other accounts.",
            one: "Its %1$lld scheduled items are deleted, including %2$lld transfer to or from another account.",
            count: transfers,
            count,
            transfers,
        )
    }

    /// The #23 message for each transaction case with `scheduled`, the D288 sentence, after its first sentence.
    static func message(transactions count: Int, transfers: Int, scheduled: String) -> String {
        if count <= 0 {
            return FeatureText.format(
                "This account has no transactions. %@ You can undo this. Hide it instead to keep it; hidden accounts still count toward net wealth.",
                scheduled,
            )
        }
        if transfers <= 0 {
            return FeatureText.pluralFormat(
                "This deletes %1$lld transactions. %2$@ Attachments are deleted too. You can undo this. Hide it instead to keep everything; hidden accounts still count toward net wealth.",
                one:
                    "This deletes %1$lld transaction. %2$@ Attachments are deleted too. You can undo this. Hide it instead to keep everything; hidden accounts still count toward net wealth.",
                count: count,
                count,
                scheduled,
            )
        }
        if count == 1 {
            return FeatureText.format(
                "This deletes 1 transaction, a transfer to or from another account whose balance will change. %@ Attachments are deleted too. You can undo this. Hide it instead to keep everything; hidden accounts still count toward net wealth.",
                scheduled,
            )
        }
        return FeatureText.pluralFormat(
            "This deletes %1$lld transactions, including %2$lld transfers to or from other accounts whose balances will change. %3$@ Attachments are deleted too. You can undo this. Hide it instead to keep everything; hidden accounts still count toward net wealth.",
            one:
                "This deletes %1$lld transactions, including %2$lld transfer to or from another account whose balance will change. %3$@ Attachments are deleted too. You can undo this. Hide it instead to keep everything; hidden accounts still count toward net wealth.",
            count: transfers,
            count,
            transfers,
            scheduled,
        )
    }
}
