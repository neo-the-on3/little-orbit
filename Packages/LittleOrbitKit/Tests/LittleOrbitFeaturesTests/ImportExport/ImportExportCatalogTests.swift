import Foundation
import Testing

/// Every text the CSV screens build is in the String Catalog, and each plural form shows its number (#30).
@Suite("CSV import and export text (#30)")
struct ImportExportCatalogTests {
    static let sourceFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/LittleOrbitFeatures/ImportExport")

    static let sourceFiles = ["ImportExportText", "ImportExportText+Review", "ImportExportText+Issues"]

    /// The first string literal after each `FeatureText.string(`, `.plural(` and `.format(` call. An
    /// interpolated `\(text)` becomes `%@`, the placeholder its catalog key has (only text is interpolated here).
    static func keys() throws -> [String] {
        let pattern = try Regex(#"FeatureText\.(?:string|plural|format)\(\s*"((?:[^"\\]|\\.)*)""#)
        return try sourceFiles.flatMap { name in
            let source = try String(contentsOf: sourceFolder.appending(path: name + ".swift"), encoding: .utf8)
            return source.matches(of: pattern)
                .compactMap { match in
                    match.output[1].substring.map { String($0).replacing(/\\\([^)]*\)/, with: "%@") }
                }
        }
    }

    static func catalog() throws -> [String: Any] {
        let data = try Data(contentsOf: StringCatalogTests.catalogURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["strings"] as? [String: Any])
    }

    @Test("Each key the CSV screens use has a catalog entry")
    func keysInCatalog() throws {
        let keys = try Self.keys()
        let catalog = try Self.catalog()
        #expect(keys.count > 100)
        #expect(keys.filter { catalog[$0] == nil } == [])
    }

    @Test("Each CSV plural entry has its count in every form")
    func pluralsShowCount() throws {
        let catalog = try Self.catalog()
        for key in try Self.keys() where key.contains("%lld") {
            let entry = try #require(catalog[key] as? [String: Any])
            let localizations = try #require(entry["localizations"] as? [String: Any])
            let english = try #require(localizations["en"] as? [String: Any])
            guard let variations = english["variations"] as? [String: Any],
                let plural = variations["plural"] as? [String: Any]
            else {
                continue
            }
            for (form, value) in plural {
                let unit = (value as? [String: Any])?["stringUnit"] as? [String: Any]
                let text = unit?["value"] as? String ?? ""
                #expect(text.contains("%lld"), "\(key) [\(form)]")
            }
        }
    }
}
