import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// A file opened from outside the app (#189 I9 to I13, D387.4): iOS Open in and the share sheet, and the Mac Dock,
/// Finder and window drop. Every route ends in the import sheet's own open path, so a Debit & Credit file is read
/// exactly as when it's picked there (#194 part 7, D439.2). File names are made up.
@Suite("Opening a CSV from outside the app (#189, D387.4)")
struct ExternalImportRouteTests {
    typealias Route = ExternalImportRoute

    static let riverstone = URL(fileURLWithPath: "/tmp/riverstone_oct.csv")
    static let harbor = URL(fileURLWithPath: "/tmp/harbor_nov.csv")

    @Test("Given one file and nothing open, When it's opened from outside, Then the import opens with it")
    func oneFileOpens() {
        let route = Route.route([Self.riverstone], importInProgress: nil, hasUnsavedEdits: false)
        #expect(route == .open(Self.riverstone))
    }

    @Test("Given an import past its file step, When another file is opened, Then the first stays and an alert shows")
    func importInProgressKeepsIt() {
        let route = Route.route([Self.harbor], importInProgress: "riverstone_oct.csv", hasUnsavedEdits: false)
        #expect(route == .finishImportFirst(current: "riverstone_oct.csv", new: "harbor_nov.csv"))
    }

    @Test("Given a sheet with unsaved edits, When a file is opened, Then it waits until the sheet closes (I12)")
    func unsavedEditsWait() {
        let route = Route.route([Self.riverstone], importInProgress: nil, hasUnsavedEdits: true)
        #expect(route == .afterSheetsClose(Self.riverstone))
    }

    @Test("Given an import in progress and unsaved edits, Then the import in progress is named first (I11)")
    func importInProgressBeforeUnsavedEdits() {
        let route = Route.route([Self.harbor], importInProgress: "riverstone_oct.csv", hasUnsavedEdits: true)
        #expect(route == .finishImportFirst(current: "riverstone_oct.csv", new: "harbor_nov.csv"))
    }

    @Test("Given the Mac app, When two files are dropped at once, Then nothing opens and one alert shows (I13)")
    func twoFilesRefused() {
        for importInProgress in [nil, "riverstone_oct.csv"] {
            for unsaved in [false, true] {
                let route = Route.route(
                    [Self.riverstone, Self.harbor],
                    importInProgress: importInProgress,
                    hasUnsavedEdits: unsaved,
                )
                #expect(route == .oneFileAtATime)
            }
        }
    }

    @Test("No file is nothing to do")
    func noFile() {
        #expect(Route.route([], importInProgress: nil, hasUnsavedEdits: false) == .ignore)
    }

    @Test("A web link is not a file to import")
    func webLinkIgnored() throws {
        let link = try #require(URL(string: "https://example.com/riverstone_oct.csv"))
        #expect(Route.route([link], importInProgress: nil, hasUnsavedEdits: false) == .ignore)
    }

    @Test("Only a file to open or to wait for has a URL to open")
    func fileToOpen() {
        #expect(Route.open(Self.riverstone).file == Self.riverstone)
        #expect(Route.afterSheetsClose(Self.riverstone).file == nil)
        #expect(Route.oneFileAtATime.file == nil)
        #expect(Route.ignore.file == nil)
    }

    @Test("The D387.4 alerts have their exact copy, with OK only")
    func alertCopy() throws {
        let finish = try #require(Route.finishImportFirst(current: "riverstone_oct.csv", new: "harbor_nov.csv").alert)
        #expect(finish.title == "Finish This Import First")
        #expect(
            finish.message
                == "Finish or cancel the import of “riverstone_oct.csv”, then open “harbor_nov.csv” again."
        )
        let single = try #require(Route.oneFileAtATime.alert)
        #expect(single.title == "Import One File at a Time")
        #expect(single.message == "Drop a single file to import it. Nothing was imported.")
        #expect(Route.open(Self.riverstone).alert == nil)
        #expect(Route.afterSheetsClose(Self.riverstone).alert == nil)
        #expect(Route.ignore.alert == nil)
    }
}

/// iOS copies a file shared from another app into the app's Documents/Inbox. It's removed once read, so no copy of
/// a statement stays in the app's folder (#189 I9).
@Suite("Open in copies on iOS (#189 I9)")
struct ExternalImportInboxTests {
    static let documents = URL(fileURLWithPath: "/var/mobile/Containers/Data/Application/AAAA/Documents")

    @Test("A file in Documents/Inbox is the system's copy")
    func inboxCopy() {
        let url = Self.documents.appending(path: "Inbox/riverstone_oct.csv")
        #expect(ExternalImportFiles.isInboxCopy(url, documents: Self.documents))
    }

    @Test("A file opened in place, or elsewhere in Documents, is not removed")
    func notInbox() {
        #expect(
            !ExternalImportFiles.isInboxCopy(
                URL(fileURLWithPath: "/tmp/riverstone_oct.csv"),
                documents: Self.documents,
            )
        )
        #expect(
            !ExternalImportFiles.isInboxCopy(
                Self.documents.appending(path: "riverstone_oct.csv"),
                documents: Self.documents,
            )
        )
        #expect(
            !ExternalImportFiles.isInboxCopy(
                Self.documents.appending(path: "InboxOld/riverstone_oct.csv"),
                documents: Self.documents,
            )
        )
        #expect(!ExternalImportFiles.isInboxCopy(Self.documents.appending(path: "Inbox"), documents: Self.documents))
    }

    @Test("A path that climbs out of Inbox is not the system's copy")
    func dotDot() {
        let url = URL(fileURLWithPath: Self.documents.path + "/Inbox/../riverstone_oct.csv")
        #expect(!ExternalImportFiles.isInboxCopy(url, documents: Self.documents))
    }
}

/// Which import is open past its file step, in any window, for D387.4's “Finish This Import First”.
@MainActor
@Suite("Imports in progress (#189 I11)")
struct ActiveImportsTests {
    @Test("Given no import, Then none is in progress")
    func empty() {
        #expect(ActiveImports().inProgress == nil)
    }

    @Test("Given an import shown in one window, Then it's in progress until that sheet closes")
    func shownThenClosed() {
        let imports = ActiveImports()
        let id = UUID()
        imports.began(id, fileName: "riverstone_oct.csv")
        #expect(imports.inProgress == "riverstone_oct.csv")
        imports.ended(id)
        #expect(imports.inProgress == nil)
    }

    @Test("Given imports in two windows, Then the first still open is named")
    func twoWindows() {
        let imports = ActiveImports()
        let first = UUID()
        let second = UUID()
        imports.began(first, fileName: "riverstone_oct.csv")
        imports.began(second, fileName: "harbor_nov.csv")
        #expect(imports.inProgress == "riverstone_oct.csv")
        imports.ended(first)
        #expect(imports.inProgress == "harbor_nov.csv")
        imports.ended(UUID())
        #expect(imports.inProgress == "harbor_nov.csv")
    }

    @Test("The feature keeps one list for every window")
    func sharedByFeature() {
        let repository = InMemoryLedgerRepository()
        let feature = ImportExportFeature(
            useCases: ImportExportUseCases(
                importing: ImportUseCases(repository: repository),
                exporting: DefaultExportTransactionsUseCase(repository: repository),
                defaultCurrency: "INR",
            )
        )
        feature.activeImports.began(UUID(), fileName: "riverstone_oct.csv")
        #expect(feature.activeImports.inProgress == "riverstone_oct.csv")
    }
}
