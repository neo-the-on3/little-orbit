import Foundation
import LittleOrbitDomain
import Testing

/// D195.2, D195.7, L3, L4: the path rules for a picked archive, before anything is extracted.
@Suite("Backup archive safety")
struct BackupArchiveSafetyTests {
    private func file(_ path: String, _ text: String = "x") -> BackupArchiveEntry {
        BackupArchiveEntry(path: path, kind: .file(Data(text.utf8)))
    }

    @Test("Regular files and folders become the snapshot's files")
    func regular() throws {
        let files = try BackupArchiveSafety.files(from: [
            BackupArchiveEntry(path: ".", kind: .directory),
            BackupArchiveEntry(path: "accounts", kind: .directory),
            BackupArchiveEntry(path: "accounts/A/", kind: .directory),
            file("manifest.json", "m"),
            file("./shared.json", "s"),
            file("accounts/A/2026.json", "y"),
        ])
        #expect(files.paths == ["accounts/A/2026.json", "manifest.json", "shared.json"])
        #expect(files["shared.json"] == Data("s".utf8))
    }

    @Test(
        "Absolute paths and .. components are damaged",
        arguments: ["/etc/passwd", "../shared.json", "accounts/../../x.json", "accounts/..", "a//b", "", "a\\b"],
    )
    func outside(path: String) {
        #expect(throws: BackupError.damaged) {
            try BackupArchiveSafety.files(from: [file("manifest.json"), file(path)])
        }
    }

    @Test("Symbolic and hard links are damaged, inside the archive or not (D195.1, L3)")
    func links() {
        let links: [BackupArchiveEntry.Kind] = [
            .symbolicLink(target: "/Users/someone/Documents"),
            .symbolicLink(target: "../outside"),
            .symbolicLink(target: "shared.json"),
            .hardLink(target: "/etc/hosts"),
            .hardLink(target: "shared.json"),
            .other,
        ]
        for kind in links {
            #expect(throws: BackupError.damaged) {
                try BackupArchiveSafety.files(from: [
                    file("shared.json"), BackupArchiveEntry(path: "attachments/A", kind: kind),
                ])
            }
        }
    }

    @Test("A directory entry outside the folder is damaged too")
    func directoryOutside() {
        #expect(throws: BackupError.damaged) {
            try BackupArchiveSafety.files(from: [BackupArchiveEntry(path: "../x", kind: .directory)])
        }
    }

    @Test("The same path twice is damaged")
    func duplicate() {
        #expect(throws: BackupError.damaged) {
            try BackupArchiveSafety.files(from: [file("shared.json", "a"), file("./shared.json", "b")])
        }
    }
}
