import Foundation
import LittleOrbitFeatures
import Testing

/// A file opened from outside the app while a sheet is up waits for this window's sheets to close, driven by the
/// sheet count and never by a timer (#189 I12, D387.4, Tech Architect on #339). Only one file waits: a newer one
/// replaces it. File names are made up.
@Suite("A file waiting for the sheets to close (#189 I12)")
struct ExternalImportPendingTests {
    typealias Route = ExternalImportRoute

    static let riverstone = URL(fileURLWithPath: "/tmp/riverstone_oct.csv")
    static let harbor = URL(fileURLWithPath: "/tmp/harbor_nov.csv")

    @Test("Given no sheet, When a file is opened, Then the import opens with it now")
    func noSheetPresentsNow() {
        var pending = Route.Pending()
        #expect(pending.receive(.open(Self.riverstone), sheetsOpen: 0) == .present(Self.riverstone))
        #expect(pending.file == nil)
        #expect(pending.sheetsChanged(to: 0) == nil)
    }

    @Test("Given an untouched sheet, When a file is opened, Then it closes and the import opens once it's gone")
    func untouchedSheetClosesThenPresentsOnce() {
        var pending = Route.Pending()
        #expect(pending.receive(.open(Self.riverstone), sheetsOpen: 1) == .closeSheetsThenPresent)
        #expect(pending.file == Self.riverstone)
        #expect(pending.sheetsChanged(to: 0) == Self.riverstone)
        #expect(pending.file == nil)
        #expect(pending.sheetsChanged(to: 0) == nil)
    }

    @Test("Given a sheet with edits, When a file is opened, Then it waits while any sheet is up and opens once")
    func sheetWithEditsWaits() {
        var pending = Route.Pending()
        #expect(pending.receive(.afterSheetsClose(Self.riverstone), sheetsOpen: 2) == .wait)
        #expect(pending.sheetsChanged(to: 2) == nil)
        #expect(pending.sheetsChanged(to: 1) == nil)
        #expect(pending.file == Self.riverstone)
        #expect(pending.sheetsChanged(to: 0) == Self.riverstone)
        #expect(pending.sheetsChanged(to: 1) == nil)
        #expect(pending.sheetsChanged(to: 0) == nil)
    }

    @Test("Given a file waiting, When another is opened, Then it replaces the first and only it opens, once")
    func secondOpenReplaces() {
        var pending = Route.Pending()
        _ = pending.receive(.afterSheetsClose(Self.riverstone), sheetsOpen: 1)
        #expect(pending.receive(.afterSheetsClose(Self.harbor), sheetsOpen: 1) == .wait)
        #expect(pending.file == Self.harbor)
        #expect(pending.sheetsChanged(to: 0) == Self.harbor)
        #expect(pending.sheetsChanged(to: 0) == nil)
    }

    @Test("Given a file waiting, When the edits are saved and another file opens, Then it replaces the first")
    func untouchedOpenReplacesWaiting() {
        var pending = Route.Pending()
        _ = pending.receive(.afterSheetsClose(Self.riverstone), sheetsOpen: 1)
        #expect(pending.receive(.open(Self.harbor), sheetsOpen: 1) == .closeSheetsThenPresent)
        #expect(pending.file == Self.harbor)
        #expect(pending.sheetsChanged(to: 0) == Self.harbor)
    }

    @Test("Given a stale waiting file and no sheet, When a file is opened, Then only the new one opens")
    func newOpenWithNoSheetDropsStale() {
        var pending = Route.Pending()
        _ = pending.receive(.afterSheetsClose(Self.riverstone), sheetsOpen: 1)
        #expect(pending.receive(.open(Self.harbor), sheetsOpen: 0) == .present(Self.harbor))
        #expect(pending.file == nil)
        #expect(pending.sheetsChanged(to: 0) == nil)
    }

    @Test("Given a file waiting, When an alert route or a web link arrives, Then the waiting file is kept")
    func alertsKeepWaitingFile() {
        var pending = Route.Pending()
        _ = pending.receive(.afterSheetsClose(Self.riverstone), sheetsOpen: 1)
        #expect(pending.receive(.oneFileAtATime, sheetsOpen: 1) == .showAlert)
        let finish = Route.finishImportFirst(current: "riverstone_oct.csv", new: "harbor_nov.csv")
        #expect(pending.receive(finish, sheetsOpen: 1) == .showAlert)
        #expect(pending.receive(.ignore, sheetsOpen: 1) == .nothing)
        #expect(pending.file == Self.riverstone)
        #expect(pending.sheetsChanged(to: 0) == Self.riverstone)
    }
}
