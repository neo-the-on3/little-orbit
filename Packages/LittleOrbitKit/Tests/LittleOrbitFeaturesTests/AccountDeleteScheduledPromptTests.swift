import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// D288: the account delete confirmation says the account's scheduled items are deleted too, one sentence after the
/// first; with none, the #23 message is unchanged.
@Suite("Account delete confirmation with scheduled items (D288)")
struct AccountDeleteScheduledPromptTests {
    private static let rest =
        "Attachments are deleted too. You can undo this. Hide it instead to keep everything; hidden accounts still count toward net wealth."

    private let travel = Account(name: "Travel Card", type: .creditCard, currencyCode: "INR")

    @Test(
        "D288: the scheduled sentence for each case, after the first sentence",
        arguments: [
            (1, 0, "This deletes 12 transactions. Its scheduled item is deleted. \(rest)"),
            (
                1, 1,
                "This deletes 12 transactions. Its scheduled item, a transfer to or from another account, is deleted. \(rest)",
            ),
            (3, 0, "This deletes 12 transactions. Its 3 scheduled items are deleted. \(rest)"),
            (
                3, 1,
                "This deletes 12 transactions. Its 3 scheduled items are deleted, including 1 transfer to or from another account. \(rest)",
            ),
            (
                4, 2,
                "This deletes 12 transactions. Its 4 scheduled items are deleted, including 2 transfers to or from other accounts. \(rest)",
            ),
        ],
    )
    func scheduledSentence(items: Int, transfers: Int, expected: String) {
        let impact = AccountDeletionImpact(
            transactionCount: 12,
            transferCount: 0,
            scheduledItemCount: items,
            scheduledTransferCount: transfers,
        )
        #expect(AccountDeletePrompt(account: travel, impact: impact).message == expected)
    }

    @Test(
        "D288: every transaction case keeps its own first sentence and tail",
        arguments: [
            (
                0, 0,
                "This account has no transactions. Its scheduled item is deleted. You can undo this. Hide it instead to keep it; hidden accounts still count toward net wealth.",
            ),
            (1, 0, "This deletes 1 transaction. Its scheduled item is deleted. \(rest)"),
            (
                1, 1,
                "This deletes 1 transaction, a transfer to or from another account whose balance will change. Its scheduled item is deleted. \(rest)",
            ),
            (
                12, 1,
                "This deletes 12 transactions, including 1 transfer to or from another account whose balance will change. Its scheduled item is deleted. \(rest)",
            ),
            (
                120, 3,
                "This deletes 120 transactions, including 3 transfers to or from other accounts whose balances will change. Its scheduled item is deleted. \(rest)",
            ),
        ],
    )
    func transactionCases(transactions: Int, transfers: Int, expected: String) {
        let impact = AccountDeletionImpact(
            transactionCount: transactions,
            transferCount: transfers,
            scheduledItemCount: 1,
        )
        #expect(AccountDeletePrompt(account: travel, impact: impact).message == expected)
    }

    @Test("With no scheduled items the #23 message is unchanged")
    func none() {
        let impact = AccountDeletionImpact(transactionCount: 12, transferCount: 0)
        #expect(
            AccountDeletePrompt(account: travel, impact: impact).message == "This deletes 12 transactions. \(Self.rest)"
        )
    }

    @Test("Items on the account count from either side of a transfer; others don't")
    func counts() {
        let account = UUID()
        let other = UUID()
        let day = CalendarDay(year: 2026, month: 10, day: 1)
        func item(_ type: TransactionType, from: UUID, toward: UUID? = nil) -> ScheduledItem {
            ScheduledItem(
                type: type,
                amount: 10,
                accountID: from,
                transferAccountID: toward,
                startDay: day,
                timeZoneID: "UTC",
                createdAt: Date(),
            )
        }
        let items = [
            item(.expense, from: account),
            item(.transfer, from: other, toward: account),
            item(.transfer, from: account, toward: other),
            item(.expense, from: other),
        ]
        let impact = AccountDeletionImpact(transactionCount: 0, transferCount: 0)
            .adding(scheduled: items, accountID: account)
        #expect(impact.scheduledItemCount == 3)
        #expect(impact.scheduledTransferCount == 2)
    }

    @Test("Every new entry is in the catalog, and every plural form uses its number")
    func catalog() throws {
        let data = try Data(contentsOf: StringCatalogTests.catalogURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: [String: Any]])
        let keys = [
            "Its scheduled item is deleted.",
            "Its scheduled item, a transfer to or from another account, is deleted.",
            "Its %lld scheduled items are deleted.",
            "Its %1$lld scheduled items are deleted, including %2$lld transfers to or from other accounts.",
            "This account has no transactions. %@ You can undo this. Hide it instead to keep it; hidden accounts still count toward net wealth.",
            "This deletes %1$lld transactions. %2$@ \(Self.rest)",
            "This deletes 1 transaction, a transfer to or from another account whose balance will change. %@ \(Self.rest)",
            "This deletes %1$lld transactions, including %2$lld transfers to or from other accounts whose balances will change. %3$@ \(Self.rest)",
        ]
        for key in keys {
            let entry = try #require(strings[key], "\(key) is in the catalog")
            #expect((entry["comment"] as? String)?.isEmpty == false)
            let english = try #require((entry["localizations"] as? [String: Any])?["en"] as? [String: Any])
            for form in Self.pluralForms(in: english) {
                #expect(form.contains("%"), "\(key): the plural form “\(form)” uses its number")
            }
        }
    }

    @Test("D344 (2), D236.2: the slot holds one whole sentence, in the same place in every case")
    func slotSentence() {
        let sentences = [
            AccountDeletePrompt.scheduledSentence(items: 1, transfers: 0),
            AccountDeletePrompt.scheduledSentence(items: 1, transfers: 1),
            AccountDeletePrompt.scheduledSentence(items: 3, transfers: 0),
            AccountDeletePrompt.scheduledSentence(items: 3, transfers: 2),
        ]
        for case let sentence? in sentences {
            // One complete sentence: a capital first, one full stop, last.
            #expect(sentence.first?.isUppercase == true)
            #expect(sentence.hasSuffix("."))
            #expect(sentence.filter { $0 == "." }.count == 1)
            for (transactions, transfers) in [(0, 0), (1, 0), (1, 1), (12, 0), (12, 3)] {
                let message = AccountDeletePrompt.message(
                    transactions: transactions,
                    transfers: transfers,
                    scheduled: sentence,
                )
                let plain = AccountDeletePrompt.message(transactions: transactions, transfers: transfers)
                // Right after the host's first sentence, with the host's own text unchanged around it.
                let first = String(plain[...(plain.firstIndex(of: ".") ?? plain.startIndex)])
                #expect(message.hasPrefix("\(first) \(sentence) "))
                #expect(message.replacingOccurrences(of: " \(sentence)", with: "") == plain)
            }
        }
        #expect(AccountDeletePrompt.scheduledSentence(items: 0, transfers: 0) == nil)
    }

    /// Every plural form in a catalog localization: its own `variations`, and its substitutions'.
    private static func pluralForms(in localization: [String: Any]) -> [String] {
        func forms(_ variations: Any?) -> [String] {
            guard let plural = (variations as? [String: Any])?["plural"] as? [String: Any] else {
                return []
            }
            return plural.values.compactMap {
                (($0 as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
            }
        }
        let substitutions =
            (localization["substitutions"] as? [String: Any])?.values
            .map {
                forms(($0 as? [String: Any])?["variations"])
            } ?? []
        return forms(localization["variations"]) + substitutions.flatMap { $0 }
    }
}
