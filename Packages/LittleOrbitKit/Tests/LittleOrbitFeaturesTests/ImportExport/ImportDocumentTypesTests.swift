import Foundation
import Testing

/// The shared iOS and Mac Info.plist lists the files the system may hand the app (#189 I9, I10): CSV and TSV only,
/// as two named types (D451.2, D451.4), never as their default app, and opened in place on iOS so no copy is kept.
@Suite("Import document types in Info.plist (#189)")
struct ImportDocumentTypesTests {
    static let configURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Config")
    static let plistURL = configURL.appending(path: "LittleOrbit-Info.plist")

    static func plist() throws -> [String: Any] {
        let data = try Data(contentsOf: plistURL)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(object as? [String: Any])
    }

    @Test("Given the app, Then it opens CSV and TSV files as two Viewer types, never as their default app (D451.4)")
    func documentTypes() throws {
        let types = try #require(try Self.plist()["CFBundleDocumentTypes"] as? [[String: Any]])
        #expect(types.map { $0["CFBundleTypeName"] as? String } == ["CSV File", "TSV File"])
        #expect(
            types.map { $0["LSItemContentTypes"] as? [String] }
                == [["public.comma-separated-values-text"], ["public.tab-separated-values-text"]]
        )
        for type in types {
            #expect(type["CFBundleTypeRole"] as? String == "Viewer")
            #expect(type["LSHandlerRank"] as? String == "Alternate")
        }
    }

    @Test("Given D451.2, Then plain text isn't a document type")
    func noPlainText() throws {
        let types = try #require(try Self.plist()["CFBundleDocumentTypes"] as? [[String: Any]])
        let all = types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        #expect(!all.contains("public.plain-text"))
        #expect(!all.contains("public.text"))
    }

    @Test("Given InfoPlist.xcstrings, Then each document type name has an English entry and a translator comment")
    func typeNamesLocalized() throws {
        let types = try #require(try Self.plist()["CFBundleDocumentTypes"] as? [[String: Any]])
        let data = try Data(contentsOf: Self.configURL.appending(path: "InfoPlist.xcstrings"))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["sourceLanguage"] as? String == "en")
        let strings = try #require(root["strings"] as? [String: Any])
        for name in types.compactMap({ $0["CFBundleTypeName"] as? String }) {
            let entry = try #require(strings[name] as? [String: Any], "\(name)")
            #expect((entry["comment"] as? String)?.contains("file type little-orbit can open") == true, "\(name)")
            let english = (entry["localizations"] as? [String: Any])?["en"] as? [String: Any]
            let unit = english?["stringUnit"] as? [String: Any]
            #expect(unit?["value"] as? String == name)
        }
    }

    @Test("Given the project, Then InfoPlist.xcstrings is a resource of the iOS and Mac apps")
    func catalogInProject() throws {
        let root = Self.configURL.deletingLastPathComponent()
        let project = try String(
            contentsOf: root.appending(path: "LittleOrbit.xcodeproj/project.xcproj"),
            encoding: .utf8,
        )
        let entry = try Regex(
            #""path": "InfoPlist\.xcstrings",\s*"target-membership": \[\s*"LittleOrbit iOS/resources",\s*"#
                + #""LittleOrbit macOS/resources",\s*\]"#
        )
        #expect(project.contains(entry))
    }

    @Test("Given iOS, Then a file from Files is opened in place")
    func opensInPlace() throws {
        #expect(try Self.plist()["LSSupportsOpeningDocumentsInPlace"] as? Bool == true)
    }

    @Test("The backup type is still exported as before")
    func backupTypeKept() throws {
        let exported = try #require(try Self.plist()["UTExportedTypeDeclarations"] as? [[String: Any]])
        #expect(exported.map { $0["UTTypeIdentifier"] as? String } == ["app.littleorbit.backup"])
    }
}
