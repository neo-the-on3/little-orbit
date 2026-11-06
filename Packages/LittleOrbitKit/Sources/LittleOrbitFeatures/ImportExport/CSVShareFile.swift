import Foundation
import LittleOrbitDomain

/// Puts an export on disk for the share sheet (#189 E3): its bytes under its own name, such as
/// `little-orbit_2026-10-25.tsv`, so Save to Files writes the same file and name as Export. Each share gets a fresh
/// folder in the temporary directory, and the folders from earlier shares are removed first. The file stays on this
/// device unless the user picks a destination in the share sheet (D14).
public enum CSVShareFile {
    /// `tmp/CSV Share`, which holds only these files.
    public static var defaultRoot: URL {
        FileManager.default.temporaryDirectory.appending(path: "CSV Share", directoryHint: .isDirectory)
    }

    /// Writes `export` into a new folder under `root` and returns the file's URL.
    public static func write(_ export: TransactionExport, under root: URL = defaultRoot) throws -> URL {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: root.path(percentEncoded: false)) {
            try fileManager.removeItem(at: root)
        }
        let folder = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: export.fileName, directoryHint: .notDirectory)
        try export.data.write(to: file, options: .atomic)
        return file
    }
}
