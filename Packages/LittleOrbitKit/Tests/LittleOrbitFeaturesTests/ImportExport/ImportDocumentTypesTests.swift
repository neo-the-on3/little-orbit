import Foundation
import Testing

/// The shared iOS and Mac Info.plist lists the files the system may hand the app (#189 I9, I10): CSV and TSV only,
/// never as their default app, and opened in place on iOS so no copy is kept.
@Suite("Import document types in Info.plist (#189)")
struct ImportDocumentTypesTests {
    static let plistURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Config/LittleOrbit-Info.plist")

    static func plist() throws -> [String: Any] {
        let data = try Data(contentsOf: plistURL)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(object as? [String: Any])
    }

    @Test("Given the app, Then it can open CSV and TSV files as a viewer, never as their default app")
    func documentTypes() throws {
        let types = try #require(try Self.plist()["CFBundleDocumentTypes"] as? [[String: Any]])
        #expect(types.count == 1)
        let type = try #require(types.first)
        #expect(type["CFBundleTypeRole"] as? String == "Viewer")
        #expect(type["LSHandlerRank"] as? String == "Alternate")
        #expect(
            type["LSItemContentTypes"] as? [String]
                == ["public.comma-separated-values-text", "public.tab-separated-values-text"]
        )
        #expect((type["CFBundleTypeName"] as? String)?.isEmpty == false)
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
