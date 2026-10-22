import Foundation
import Testing

/// Every sentence the Backups copy reads through `FeatureText` is a catalog entry whose English is the same text,
/// so the catalog and the Linux English never drift apart.
@Suite("Backups copy in the String Catalog")
struct BackupCatalogTests {
    /// Packages/LittleOrbitKit/Sources/LittleOrbitFeatures, from this file's path.
    private static let features = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/LittleOrbitFeatures")

    @Test("Each FeatureText key in the Backups copy is in the catalog with the same English")
    func everyKeyIsInTheCatalog() throws {
        let catalog = try Self.catalog()
        var checked = 0
        for file in ["BackupPresentation.swift", "BackupPresentation+DeviceCopy.swift", "BackupsViewModel.swift"] {
            let source = try String(
                contentsOf: Self.features.appendingPathComponent("Backups/\(file)"),
                encoding: .utf8,
            )
            for (key, one) in Self.keys(in: source) {
                checked += 1
                let entry = catalog[key]
                #expect(entry?.other == key, "\(key)")
                #expect(entry?.one == one, "\(key)")
            }
        }
        #expect(checked > 80)
    }

    private struct Entry: Equatable {
        var other: String?
        var one: String?
    }

    private static func catalog() throws -> [String: Entry] {
        let url = features.appendingPathComponent("Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = json?["strings"] as? [String: [String: Any]] ?? [:]
        return strings.mapValues { entry in
            let english = (entry["localizations"] as? [String: Any])?["en"] as? [String: Any]
            let plural = (english?["variations"] as? [String: Any])?["plural"] as? [String: Any]
            func value(_ unit: Any?) -> String? {
                ((unit as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
            }
            return plural.map { Entry(other: value($0["other"]), one: value($0["one"])) }
                ?? Entry(other: value(english))
        }
    }

    /// The literal after each `FeatureText.format(` and `FeatureText.plural(`, and a plural's `one:` literal.
    private static func keys(in source: String) -> [(String, String?)] {
        var keys: [(String, String?)] = []
        var rest = Substring(source)
        while let call = rest.range(of: "FeatureText.") {
            rest = rest[call.upperBound...]
            let isPlural = rest.hasPrefix("plural(")
            guard isPlural || rest.hasPrefix("format(") else { continue }
            rest = rest.dropFirst("format(".count)
            guard let key = literal(&rest) else { continue }
            var one: String?
            if isPlural, let label = rest.range(of: "one:") {
                rest = rest[label.upperBound...]
                one = literal(&rest)
            }
            keys.append((key, one))
        }
        return keys
    }

    /// Reads a string literal at the start of `text` (after whitespace), single-line or multi-line with `\`
    /// line continuations, and moves `text` past it.
    private static func literal(_ text: inout Substring) -> String? {
        text = text.drop(while: \.isWhitespace)
        if text.hasPrefix("\"\"\"") {
            text = text.dropFirst(3)
            guard let end = text.range(of: "\"\"\"") else { return nil }
            let lines = text[..<end.lowerBound].split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
            let indent = lines.last?.count ?? 0
            text = text[end.upperBound...]
            return lines.dropLast().map { $0.dropFirst(indent) }
                .reduce(into: "") { result, line in
                    result += line.hasSuffix("\\") ? String(line.dropLast()) : line + "\n"
                }
                .trimmingSuffix("\n")
        }
        guard text.hasPrefix("\"") else { return nil }
        text = text.dropFirst()
        guard let end = text.firstIndex(of: "\"") else { return nil }
        defer { text = text[text.index(after: end)...] }
        return String(text[..<end])
    }
}

extension String {
    fileprivate func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
