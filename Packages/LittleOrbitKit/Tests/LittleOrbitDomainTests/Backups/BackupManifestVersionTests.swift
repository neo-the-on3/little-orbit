import Foundation
import LittleOrbitDomain
import Testing

/// D196.2 and D197.1: the manifest's month, and its format version read before anything else (L26, L34–L38).
@Suite("Backup manifest: month and version")
struct BackupManifestVersionTests {
    private let codec = BackupCodec(hashing: FakeBackupHashing())

    private func files(month: String? = "2026-11") throws -> BackupSnapshotFiles {
        let manifest = BackupManifest(
            kind: .automatic,
            createdAt: Date(timeIntervalSince1970: 1_793_473_200),
            nameIndex: 2,
            schemaVersion: "1.0.0",
            accountCount: 0,
            transactionCount: 0,
            attachmentCount: 0,
            month: month,
        )
        return try codec.encode(BackupContents(manifest: manifest, ledger: LedgerSnapshot()))
    }

    private func manifestObject(_ files: BackupSnapshotFiles) throws -> [String: Any] {
        let data = try #require(files["manifest.json"])
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("The manifest records month as YYYY-MM, and it round-trips (L26)")
    func month() throws {
        let files = try files()
        let backup = try #require(try manifestObject(files)["backup"] as? [String: Any])
        #expect(backup["month"] as? String == "2026-11")
        #expect(try codec.decode(files).manifest.month == "2026-11")
        #expect(try codec.summary(ofManifest: #require(files["manifest.json"])).manifest.month == "2026-11")
    }

    @Test("A manifest without month is still a valid backup (L28)")
    func noMonth() throws {
        let files = try files(month: nil)
        let backup = try #require(try manifestObject(files)["backup"] as? [String: Any])
        #expect(backup["month"] == nil)
        #expect(try codec.decode(files).manifest.month == nil)
    }

    @Test(
        "A manifest without a readable version, or not JSON, is damaged (L37)",
        arguments: [
            "", "not json", "{", "[]", #"{"format":"little-orbit-backup"}"#,
            #"{"format":"little-orbit-backup","formatVersion":"2"}"#,
            #"{"format":"little-orbit-backup","formatVersion":0}"#, #"{"format":"other","formatVersion":2}"#,
        ],
    )
    func unreadableVersion(text: String) {
        #expect(throws: BackupError.damaged) { try codec.checkFormatVersion(ofManifest: Data(text.utf8)) }
        #expect(throws: BackupError.damaged) { try codec.reading(manifest: Data(text.utf8)) }
    }

    @Test("Only the version is needed to refuse a newer format, whatever else the manifest says (L34)")
    func newerOnlyNeedsTheVersion() throws {
        let manifest = Data(#"{"format":"little-orbit-backup","formatVersion":2,"files":"anything"}"#.utf8)
        #expect(throws: BackupError.newerFormat) { try codec.checkFormatVersion(ofManifest: manifest) }
        #expect(throws: BackupError.newerFormat) { try codec.decode(BackupSnapshotFiles(["manifest.json": manifest])) }
        #expect(throws: Never.self) {
            try codec.checkFormatVersion(ofManifest: #require(try files()["manifest.json"]))
        }
    }

    @Test("A newer manifest is read for the list with what it says in format 1's shape (L35)")
    func newerForTheList() throws {
        var object = try manifestObject(try files())
        object["formatVersion"] = 2
        let data = try JSONSerialization.data(withJSONObject: object)
        guard case .newer(let hints) = try codec.reading(manifest: data) else {
            Issue.record("Expected a newer format")
            return
        }
        #expect(hints.formatVersion == 2)
        #expect(hints.kind == .automatic)
        #expect(hints.createdAt == Date(timeIntervalSince1970: 1_793_473_200))
        #expect(hints.nameIndex == 2)
        #expect(hints.month == "2026-11")

        let bare = Data(#"{"format":"little-orbit-backup","formatVersion":7,"backup":"new shape"}"#.utf8)
        guard case .newer(let little) = try codec.reading(manifest: bare) else {
            Issue.record("Expected a newer format")
            return
        }
        #expect(little.formatVersion == 7)
        #expect(little.createdAt == nil)
    }
}
