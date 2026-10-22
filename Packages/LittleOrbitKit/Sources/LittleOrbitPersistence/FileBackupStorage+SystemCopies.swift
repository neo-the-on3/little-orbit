import Foundation
import LittleOrbitDomain

/// The save panel's copies of an export (Tester finding 3 on 4c8b0b3). SwiftUI's `fileExporter` writes the document
/// to `tmp/<uuid>/<suggested name>` in the app's container for the system panel and doesn't remove it, on iPhone
/// after Cancel and on iPad after Save. Only a regular file named the way an export is named, in `tmp` itself or
/// directly in a `<uuid>` folder there, is removed, and the `<uuid>` folder too once it's empty. Nothing else in
/// `tmp` is touched. Copies the system keeps outside the app's container are out of reach.
extension FileBackupStorage {
    public func removeSystemExportCopies() {
        guard let tmp = systemTemporaryFolder else {
            return
        }
        removeExportCopies(in: tmp)
        let names = (try? fileManager.contentsOfDirectory(atPath: tmp.path)) ?? []
        for name in names where UUID(uuidString: name) != nil {
            let folder = tmp.appendingPathComponent(name, isDirectory: true)
            guard isPlainDirectory(folder), removeExportCopies(in: folder) else {
                continue
            }
            if (try? fileManager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
                try? fileManager.removeItem(at: folder)
            }
        }
    }

    /// Whether `name` is one an export's file gets: `little-orbit YYYY-MM-DD HHmm[ n].littleorbit-backup`, or
    /// `<uuid>.littleorbit-backup` for a name that couldn't be used (`BackupExport.fileName`).
    static func isExportFileName(_ name: String) -> Bool {
        let suffix = ".\(BackupFormat.fileExtension)"
        guard name.hasSuffix(suffix) else {
            return false
        }
        let stem = String(name.dropLast(suffix.count))
        if UUID(uuidString: stem) != nil {
            return true
        }
        return stem.wholeMatch(of: /little-orbit \d{4}-\d{2}-\d{2} \d{4}( [0-9]+)?/) != nil
    }

    /// Removes the export copies directly in `folder`. Whether any was removed.
    @discardableResult
    private func removeExportCopies(in folder: URL) -> Bool {
        var removed = false
        let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where Self.isExportFileName(name) {
            let url = folder.appendingPathComponent(name)
            if Self.isRegularFile(url), (try? fileManager.removeItem(at: url)) != nil {
                removed = true
            }
        }
        return removed
    }

    private func isPlainDirectory(_ url: URL) -> Bool {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.type] as? FileAttributeType == .typeDirectory
    }
}
