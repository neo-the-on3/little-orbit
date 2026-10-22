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
}
