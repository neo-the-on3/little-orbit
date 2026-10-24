import Foundation
import Testing

/// Guards on the package's String Catalog: user-facing text uses curly apostrophes and quotes (D199.3, #93
/// T14), and the failure titles are separate entries (D201.4, D204.2). Translator comments aren't checked.
@Suite("String Catalog")
struct StringCatalogTests {
    static let catalogURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/LittleOrbitFeatures/Resources/Localizable.xcstrings")

    /// Each key with every value under it, in every language, plural and substitution.
    static func entries() throws -> [String: [String]] {
        let data = try Data(contentsOf: catalogURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])
        return strings.mapValues { values(in: $0) }
    }

    private static func values(in node: Any) -> [String] {
        if let dictionary = node as? [String: Any] {
            return dictionary.flatMap { key, value -> [String] in
                if key == "comment" { return [] }
                if key == "stringUnit", let unit = value as? [String: Any], let text = unit["value"] as? String {
                    return [text]
                }
                return values(in: value)
            }
        }
        if let array = node as? [Any] {
            return array.flatMap { values(in: $0) }
        }
        return []
    }

    @Test("T14: no key or value has a straight ' or \"; they use ’ “ ” (D199.3)")
    func curlyPunctuation() throws {
        let entries = try Self.entries()
        #expect(!entries.isEmpty)
        for (key, values) in entries {
            for text in [key] + values {
                #expect(!text.contains("'"), "Straight apostrophe in \(text)")
                #expect(!text.contains("\""), "Straight quote in \(text)")
            }
        }
    }

    @Test("The Can’t, Couldn’t Undo or Redo and Couldn’t Make the Change titles are their own entries")
    func separateTitles() throws {
        let entries = try Self.entries()
        for key in [
            "Can’t Undo %@", "Can’t Redo %@", "Couldn’t Undo %@", "Couldn’t Redo %@", "Couldn’t Make the Change",
        ] {
            #expect(entries[key] == [key], "\(key) is one entry with its English value")
        }
    }

    @Test("D228: no stale-step message key or value names a window")
    func staleMessagesNameNoCause() throws {
        let entries = try Self.entries()
        let stale = entries.filter { $0.key.hasSuffix("Nothing was changed.") }
        #expect(stale.count >= 3)
        for (key, values) in stale {
            for text in [key] + values {
                #expect(!text.lowercased().contains("window"), "\(text) names a cause")
            }
        }
    }

    @Test("The swipe verb Refund is its own entry, apart from the noun (UI Designer, 23 Oct)")
    func refundVerb() throws {
        let entries = try Self.entries()
        #expect(entries["Refund (swipe action)"] == ["Refund"])
        #expect(entries["Refund"] == ["Refund"])
    }

    @Test("The split confirmations count refunds with plural variants, verb included (UI Designer, 23 Oct, item 4)")
    func refundCountPlurals() throws {
        let entries = try Self.entries()
        let counted = entries.filter {
            $0.key.contains("lld refunds") && ($0.key.hasPrefix("Its ") || $0.key.hasPrefix("This becomes"))
        }
        #expect(counted.count == 5)
        for (key, values) in counted {
            #expect(values.contains { $0.contains("%#@refunds@") }, "\(key) substitutes the count")
            #expect(
                values.contains { $0.hasPrefix("%arg refund ") && $0.hasSuffix("moves") },
                "\(key) has a one variant",
            )
            #expect(
                values.contains { $0.hasPrefix("%arg refunds ") && $0.hasSuffix(" move") },
                "\(key) has an other variant",
            )
        }
    }

    @Test("D248.3: the split save refusal counts refunds with a plural variant")
    func splitRefusalPlural() throws {
        let values = try #require(
            try Self.entries()[
                "This expense has %lld refunds, so it can’t be split. Remove the split to save your other changes."
            ]
        )
        #expect(
            values.contains(
                "This expense has a refund, so it can’t be split. Remove the split to save your other changes."
            )
        )
        #expect(
            values.contains(
                "This expense has %lld refunds, so it can’t be split. Remove the split to save your other changes."
            )
        )
    }

    @Test("D251.1: the refund sheet’s split message is its own whole-phrase entry")
    func refundSplitMessage() throws {
        let key = "This expense is now split, so it can’t be refunded."
        #expect(try Self.entries()[key] == [key])
    }
}
