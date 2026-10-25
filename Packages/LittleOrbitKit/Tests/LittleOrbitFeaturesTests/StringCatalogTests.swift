import Foundation
import Testing

/// Guards on the package's String Catalog: user-facing text uses curly apostrophes and quotes (D199.3, #93
/// T14), the failure titles are separate entries (D201.4, D204.2), and every plural variation shows its number,
/// which Xcode's CompileXCStrings requires and Linux can't run. Translator comments aren't checked.
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

    /// Whether `text` has a printf placeholder such as `%lld`, `%2$lld` or `%@`, or a `%#@name@` substitution.
    private static func hasPlaceholder(_ text: String) -> Bool {
        text.contains(#/%(\d+\$)?[-+ 0#]*\d*(\.\d+)?(hh|h|ll|l|q|z|t|j)?[dDiuUxXoOfeEgGcCsSpaA@]|%#@\w+@/#)
    }

    /// Each top-level plural variation in `node`, as its path and its variants' values. Plurals inside a
    /// `substitutions` entry are left out: there the `%#@name@` placeholder already takes the number, so their
    /// variants may leave it out.
    private static func pluralVariations(in node: Any, path: String) -> [(path: String, values: [String])] {
        guard let dictionary = node as? [String: Any] else {
            return []
        }
        return dictionary.flatMap { key, value -> [(path: String, values: [String])] in
            if key == "substitutions" {
                return []
            }
            if key == "plural", let forms = value as? [String: Any] {
                return [(path: "\(path)/plural", values: forms.values.flatMap { values(in: $0) })]
            }
            return pluralVariations(in: value, path: "\(path)/\(key)")
        }
    }

    @Test("Every plural variation shows its number in at least one variant, as CompileXCStrings requires")
    func pluralsShowTheirNumber() throws {
        let data = try Data(contentsOf: Self.catalogURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])
        var plurals = 0
        for (key, entry) in strings {
            for variation in Self.pluralVariations(in: entry, path: key) {
                plurals += 1
                #expect(
                    variation.values.contains(where: Self.hasPlaceholder),
                    """
                    \(variation.path): no variant shows the number. Xcode fails with “Plural variation requires \
                    referencing the number in the string”; use separate entries for one and more, or a substitution.
                    """,
                )
            }
        }
        #expect(plurals > 0)
    }

    @Test("D313.4: the Mac list's “%lld budgets” and “%lld overspent” are one/other plurals, each showing the number")
    func budgetCountPlurals() throws {
        let data = try Data(contentsOf: Self.catalogURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])
        for key in ["%lld budgets", "%lld overspent"] {
            let entry = try #require(strings[key])
            let variations = Self.pluralVariations(in: entry, path: key)
            #expect(variations.count == 1, "\(key) has one plural variation")
            for variation in variations {
                #expect(variation.values.count >= 2, "\(variation.path) has one and other")
                for value in variation.values {
                    #expect(value.contains("%lld"), "\(variation.path): “\(value)” doesn’t show the number")
                }
            }
        }
        #expect(strings["1 budget"] == nil, "The singular is the plural’s one variant, not its own entry")
    }
}
