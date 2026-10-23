import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// D236: the account delete confirmation, one whole message for each case, and the title and buttons that
/// don't change (#139).
@Suite("Account delete confirmation (D236)")
struct AccountDeletePromptTests {
    private static let rest =
        "Attachments are deleted too. You can undo this. Hide it instead to keep everything; hidden accounts still count toward net wealth."

    private let travel = Account(name: "Travel Card", type: .creditCard, currencyCode: "INR")

    @Test(
        "D236.2: the full message for each case",
        arguments: [
            (
                0, 0,
                "This account has no transactions. You can undo this. Hide it instead to keep it; hidden accounts still count toward net wealth.",
            ),
            (1, 0, "This deletes 1 transaction. \(rest)"),
            (
                1, 1,
                "This deletes 1 transaction, a transfer to or from another account whose balance will change. \(rest)",
            ),
            (12, 0, "This deletes 12 transactions. \(rest)"),
            (
                12, 1,
                "This deletes 12 transactions, including 1 transfer to or from another account whose balance will change. \(rest)",
            ),
            (
                120, 3,
                "This deletes 120 transactions, including 3 transfers to or from other accounts whose balances will change. \(rest)",
            ),
        ],
    )
    func message(transactions: Int, transfers: Int, expected: String) {
        let prompt = AccountDeletePrompt(
            account: travel,
            impact: AccountDeletionImpact(transactionCount: transactions, transferCount: transfers),
        )
        #expect(prompt.message == expected)
        #expect(!prompt.message.contains(" 0 transactions"))
    }

    @Test("D236.1: the title and the three buttons don’t change")
    func titleAndButtons() {
        let prompt = AccountDeletePrompt(
            account: travel,
            impact: AccountDeletionImpact(transactionCount: 0, transferCount: 0),
        )
        #expect(prompt.title == "Delete “Travel Card”?")
        #expect(prompt.hideTitle == "Hide Account")
        #expect(prompt.deleteTitle == "Delete Account")
        #expect(prompt.cancelTitle == "Cancel")
    }

    @Test("D236.3: four whole-message catalog entries, with comments and plural forms on every number")
    func catalogEntries() throws {
        let data = try Data(contentsOf: StringCatalogTests.catalogURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: [String: Any]])

        let empty =
            "This account has no transactions. You can undo this. Hide it instead to keep it; hidden accounts still count toward net wealth."
        let single =
            "This deletes 1 transaction, a transfer to or from another account whose balance will change. \(Self.rest)"
        for key in [empty, single] {
            let entry = try #require(strings[key], "\(key) is in the catalog")
            #expect(Self.english(entry) == key)
            #expect((entry["comment"] as? String)?.isEmpty == false)
        }

        let counted = try #require(strings["This deletes %lld transactions. \(Self.rest)"])
        #expect((counted["comment"] as? String)?.isEmpty == false)
        let plural = try #require(Self.plural(Self.en(counted)?["variations"]))
        #expect(plural["one"] == "This deletes %lld transaction. \(Self.rest)")
        #expect(plural["other"] == "This deletes %lld transactions. \(Self.rest)")

        let key =
            "This deletes %1$lld transactions, including %2$lld transfers to or from other accounts whose balances will change. \(Self.rest)"
        let transfers = try #require(strings[key])
        #expect((transfers["comment"] as? String)?.isEmpty == false)
        let localization = try #require(Self.en(transfers))
        #expect(Self.english(transfers) == "This deletes %#@transactions@, including %#@transfers@. \(Self.rest)")
        let substitutions = try #require(localization["substitutions"] as? [String: [String: Any]])
        let transactionForms = try #require(Self.plural(substitutions["transactions"]?["variations"]))
        #expect(transactionForms == ["one": "%arg transaction", "other": "%arg transactions"])
        let transferForms = try #require(Self.plural(substitutions["transfers"]?["variations"]))
        #expect(
            transferForms == [
                "one": "%arg transfer to or from another account whose balance will change",
                "other": "%arg transfers to or from other accounts whose balances will change",
            ]
        )
    }

    private static func en(_ entry: [String: Any]) -> [String: Any]? {
        (entry["localizations"] as? [String: Any])?["en"] as? [String: Any]
    }

    private static func english(_ entry: [String: Any]) -> String? {
        (en(entry)?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    private static func plural(_ variations: Any?) -> [String: String]? {
        guard let forms = (variations as? [String: Any])?["plural"] as? [String: [String: Any]] else {
            return nil
        }
        return forms.compactMapValues { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
    }
}
