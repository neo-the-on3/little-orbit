import Foundation
import Testing

@testable import LittleOrbitFeatures

/// The bulk edit toggles' VoiceOver names (#110): "Change <Field>", one per field, none the field's own name.
@Suite("Bulk edit toggle names")
struct BulkEditTextTests {
    @Test("Each toggle reads Change and its field, apart from the field itself")
    func toggleNames() {
        let names = [
            BulkEditText.changeCategory, BulkEditText.changePayee, BulkEditText.changeDescription,
            BulkEditText.changeDate, BulkEditText.changeAccount,
        ]
        #expect(
            names == ["Change Category", "Change Payee", "Change Description", "Change Date", "Change Account"]
        )
        #expect(Set(names).count == names.count)
    }

    @Test("D393.2: the deleted-selection alert, and its message as a whole-phrase plural with a translator comment")
    func deletedSelectionAlert() throws {
        #expect(BulkEditText.couldntApplyTitle == "Couldn’t Apply Changes")
        #expect(
            BulkEditText.deletedMessage(count: 1)
                == "1 of the selected transactions has been deleted. Nothing was changed."
        )
        #expect(
            BulkEditText.deletedMessage(count: 2)
                == "2 of the selected transactions have been deleted. Nothing was changed."
        )
        let key = "%lld of the selected transactions have been deleted. Nothing was changed."
        let entries = try StringCatalogTests.entries()
        let strings = try catalogStrings()
        #expect(entries["Couldn’t Apply Changes"] == ["Couldn’t Apply Changes"])
        #expect(
            Set(entries[key] ?? [])
                == [key, "%lld of the selected transactions has been deleted. Nothing was changed."]
        )
        try expectWholePhrasePlural(key)
        // N3: the Swift comment and the catalog's say the same, and OK's comment names this alert.
        let title = try #require(strings["Couldn’t Apply Changes"] as? [String: Any])
        #expect((title["comment"] as? String)?.contains("only an OK button (D393)") == true)
        let okay = try #require(strings["OK"] as? [String: Any])
        #expect((okay["comment"] as? String)?.contains("Bulk Edit alert") == true)
    }

    @Test("D396: the title and the Apply button are whole-phrase plurals for 1, 3 and 0")
    func titleAndApplyPlurals() throws {
        #expect(BulkEditText.title(count: 1) == "Edit 1 Transaction")
        #expect(BulkEditText.title(count: 3) == "Edit 3 Transactions")
        #expect(BulkEditText.applyTitle(count: 1) == "Apply to 1 Transaction")
        #expect(BulkEditText.applyTitle(count: 3) == "Apply to 3 Transactions")
        #expect(BulkEditText.title(count: 0) == "Edit 0 Transactions")
        #expect(BulkEditText.applyTitle(count: 0) == "Apply to 0 Transactions")
        let entries = try StringCatalogTests.entries()
        #expect(
            Set(entries["transactions.bulkEdit.title"] ?? []) == ["Edit %lld Transaction", "Edit %lld Transactions"]
        )
        #expect(
            Set(entries["Apply to %lld Transactions"] ?? [])
                == ["Apply to %lld Transaction", "Apply to %lld Transactions"]
        )
        try expectWholePhrasePlural(
            "transactions.bulkEdit.title",
            commentMentions: "title of the Edit Transactions sheet",
        )
        try expectWholePhrasePlural("Apply to %lld Transactions", commentMentions: "Apply button")
    }

    /// The catalog entry `key` has a translator comment naming `%lld` (and `commentMentions`), and English
    /// `one` and `other` plural forms.
    private func expectWholePhrasePlural(_ key: String, commentMentions: String = "%lld") throws {
        let strings = try catalogStrings()
        let entry = try #require(strings[key] as? [String: Any])
        let comment = try #require(entry["comment"] as? String)
        #expect(comment.contains("%lld"))
        #expect(comment.contains(commentMentions))
        let english = try #require((entry["localizations"] as? [String: Any])?["en"] as? [String: Any])
        let plural = try #require((english["variations"] as? [String: Any])?["plural"] as? [String: Any])
        #expect(Set(plural.keys) == ["one", "other"])
    }

    private func catalogStrings() throws -> [String: Any] {
        let data = try Data(contentsOf: StringCatalogTests.catalogURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["strings"] as? [String: Any])
    }
}
