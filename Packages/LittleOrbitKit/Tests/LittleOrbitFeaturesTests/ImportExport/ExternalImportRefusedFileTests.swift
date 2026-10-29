import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// D451.3: a file opened from outside the app that the import can't use gets the same alert as when it's picked in
/// the import sheet (D323.7), because it goes through the sheet's own `open(url:)`. File names and bytes are made up.
@Suite("A refused file opened from outside the app (#189, D451.3)")
@MainActor
struct ExternalImportRefusedFileTests {
    /// Writes `bytes` to a made-up file named `name` (or nothing, for a file that's gone), routes it as an open
    /// from outside the app, and opens the routed file in a new import sheet's model.
    static func openedFromOutside(_ name: String, bytes: [UInt8]?) async throws -> CSVImportViewModel {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ExternalRefused-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: name)
        if let bytes {
            try Data(bytes).write(to: url)
        }
        let route = ExternalImportRoute.route([url], importInProgress: nil, hasUnsavedEdits: false)
        let file = try #require(route.file)
        let model = ActiveImportsTests.feature().makeImport()
        await model.open(url: file)
        return model
    }

    @Test("Given a PDF named like a CSV, When it's opened from outside, Then “Can’t Import” shows D323.7's text")
    func notCSVText() async throws {
        let model = try await Self.openedFromOutside("riverstone_oct.csv", bytes: Array("%PDF-1.7\n".utf8))
        #expect(model.step == .pickFile)
        #expect(model.alert?.title == "Can’t Import “riverstone_oct.csv”")
        #expect(
            model.alert?.message
                == "This isn’t a CSV file. In a spreadsheet app, export it as CSV, then import that file. "
                + "Nothing was imported."
        )
    }

    @Test("Given a 0-byte file, When it's opened from outside, Then “Can’t Read” shows (D268.1)")
    func emptyFile() async throws {
        let model = try await Self.openedFromOutside("harbor_nov.csv", bytes: [])
        #expect(model.step == .pickFile)
        #expect(model.alert?.title == "Can’t Read “harbor_nov.csv”")
        #expect(model.alert?.message == "The file is empty. Nothing was imported.")
    }

    @Test("Given a file that can't be read, When it's opened from outside, Then “Couldn’t Open” shows (D268.6)")
    func failedRead() async throws {
        let model = try await Self.openedFromOutside("harbor_nov.csv", bytes: nil)
        #expect(model.step == .pickFile)
        #expect(model.alert?.title == "Couldn’t Open “harbor_nov.csv”")
        #expect(model.alert?.message == "little-orbit couldn’t read this file. Try again. Nothing was imported.")
    }
}
