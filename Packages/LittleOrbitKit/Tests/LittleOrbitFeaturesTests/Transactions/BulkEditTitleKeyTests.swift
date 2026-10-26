import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// The Bulk Edit sheet's title and the Undo name “Edit %lld Transactions” share their English but not their catalog
/// entry, so each translates for its own use (UI Designer, Tech Architect on #270). Each entry's comment is the one
/// its Swift call passes, and describes that use.
@Suite("Bulk edit title key apart from the Undo name")
struct BulkEditTitleKeyTests {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/LittleOrbitFeatures/Transactions")

    private static func source(_ name: String) throws -> String {
        try String(contentsOf: sources.appending(path: name), encoding: .utf8)
    }

    private static func comment(of key: String) throws -> String {
        let data = try Data(contentsOf: StringCatalogTests.catalogURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])
        let entry = try #require(strings[key] as? [String: Any], "No catalog entry \(key)")
        return try #require(entry["comment"] as? String)
    }

    @Test("The sheet title uses its own key, with the comment its Swift call passes, about the sheet title")
    func sheetTitleKey() throws {
        let text = try Self.source("BulkEditText.swift")
        let comment = try Self.comment(of: "transactions.bulkEdit.title")
        #expect(text.contains("titleKey: StaticString = \"transactions.bulkEdit.title\""))
        #expect(text.contains("key: titleKey,"))
        #expect(text.contains("\"\(comment)\""), "The Swift comment matches the catalog's")
        #expect(!text.contains("\"Edit %lld Transactions\", one:"), "The title no longer uses the Undo name's key")
        #expect(comment.contains("title of the Edit Transactions sheet"))
        #expect(!comment.contains("Undo"))
    }

    @Test("The Undo name keeps “Edit %lld Transactions”, with its Undo-menu comment matching its Swift call")
    func undoNameKey() throws {
        let undo = try Self.source("UndoActionTitle.swift")
        let comment = try Self.comment(of: "Edit %lld Transactions")
        // Exactly as on main before #270.
        #expect(comment == "Undo name: several transactions edited at once.")
        #expect(undo.contains("\"Edit \\(items.count) Transactions\",\n                    comment: \"\(comment)\""))
        #expect(!comment.contains("Bulk edit"))
    }

    @Test("At 1 and at 3, the sheet title and the Undo name resolve to different catalog keys", arguments: [1, 3])
    func differentKeys(count: Int) throws {
        let sheetKey = "\(BulkEditText.titleKey)"
        // The Undo name's key at each count: one edit is “Edit Transaction”, several “Edit %lld Transactions”.
        let undoKey = count == 1 ? "Edit Transaction" : "Edit %lld Transactions"
        #expect(sheetKey != undoKey)
        #expect(try Self.english(of: sheetKey, count: count) == BulkEditText.title(count: count))
        let undoName = UndoActionTitle.base(
            of: .replaced((0..<count).map { _ in Transaction(type: .expense, amount: 1) })
        )
        #expect(try Self.english(of: undoKey, count: count) == undoName)
    }

    /// The catalog's English for `key` at `count`: its `one` or `other` plural form, or its only form, filled in.
    private static func english(of key: String, count: Int) throws -> String {
        let data = try Data(contentsOf: StringCatalogTests.catalogURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entry = try #require((root["strings"] as? [String: Any])?[key] as? [String: Any], "No entry \(key)")
        let english = try #require((entry["localizations"] as? [String: Any])?["en"] as? [String: Any])
        let unit: Any?
        if let plural = (english["variations"] as? [String: Any])?["plural"] as? [String: Any] {
            unit = plural[count == 1 ? "one" : "other"]
        } else {
            unit = english
        }
        let value = try #require(((unit as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String)
        return value.contains("%lld") ? String(format: value, count) : value
    }
}
