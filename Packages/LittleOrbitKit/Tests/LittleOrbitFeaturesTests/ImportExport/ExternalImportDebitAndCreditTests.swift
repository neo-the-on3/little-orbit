import Foundation
import LittleOrbitDomain
import LittleOrbitPersistence
import Testing

@testable import LittleOrbitFeatures

/// #194 part 7 (D439.2): a made-up Debit & Credit file opened from outside the app is routed to the import sheet's
/// own `open(url:)`, so it's read as a Debit & Credit export, exactly as when it's picked in the import sheet.
@Suite("A Debit & Credit file opened from outside the app (#189, #194 part 7)")
@MainActor
struct ExternalImportDebitAndCreditTests {
    typealias Model = DebitAndCreditImportViewModelTests

    @Test("Given the sample file, When it's opened from outside the app, Then it's read as when it's picked")
    func readAsWhenPicked() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ExternalImport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: Model.fileName)
        try CSVFixture.data("Debit and Credit Export").write(to: url)

        let route = ExternalImportRoute.route([url], importInProgress: nil, hasUnsavedEdits: false)
        let file = try #require(route.file)
        let opened = Model.model(try Model.repository())
        await opened.open(url: file)

        let picked = Model.model(try Model.repository())
        await picked.open(data: try CSVFixture.data("Debit and Credit Export"), fileName: Model.fileName)

        #expect(opened.step == .columns)
        #expect(opened.isDebitAndCredit)
        #expect(opened.fileName == Model.fileName)
        #expect(opened.columnRows.map(\.field) == picked.columnRows.map(\.field))
        #expect(opened.formatNote == picked.formatNote)
        #expect(opened.showsReadFormat == picked.showsReadFormat)
    }
}
