import Foundation
import LittleOrbitDomain

extension FileBackupStorage {
    /// Every regular file under `base` by relative path, with its size, and whether every size could be read.
    /// A folder, `base` or one inside it, whose contents can't be listed throws a read failure: the backup can't be
    /// read at all, so it's never called damaged (R3, D214). Symlinks aren't followed. A size that can't be read
    /// leaves the file out; the list shows "Unknown" for a never-read folder, and a backup whose manifest lists the
    /// file reads as damaged, as for a missing file (D202.1, L49).
    static func fileSizes(in base: String) throws -> (sizes: [String: Int64], known: Bool) {
        let fileManager = FileManager.default
        var sizes: [String: Int64] = [:]
        var known = true
        var pending = [""]
        while let folderPath = pending.popLast() {
            let names = try reading { try fileManager.contentsOfDirectory(atPath: base + "/" + folderPath) }
            for name in names {
                let relative = folderPath.isEmpty ? name : folderPath + "/" + name
                guard let attributes = try? fileManager.attributesOfItem(atPath: base + "/" + relative) else {
                    known = false
                    continue
                }
                switch attributes[.type] as? FileAttributeType {
                case .typeRegular:
                    sizes[relative] = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                case .typeDirectory:
                    pending.append(relative)
                default:
                    break
                }
            }
        }
        return (sizes, known)
    }

    /// The folder's creation date from its own attributes, which can be read when its contents can't (D214.3).
    public func folderCreationDate(id: UUID) -> Date? {
        let url = folderURL(id)
        return (try? fileManager.attributesOfItem(atPath: url.path))?[.creationDate] as? Date
    }

    /// Gives the owner access to `url` and every folder inside it, so a folder that couldn't be read can be removed.
    /// Only for a folder already moved out of the Backups folder to be deleted (L17, D214).
    static func makeRemovable(_ url: URL) {
        let fileManager = FileManager.default
        var pending = [url.path]
        while let path = pending.popLast() {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
            for name in (try? fileManager.contentsOfDirectory(atPath: path)) ?? [] {
                let child = path + "/" + name
                if (try? fileManager.attributesOfItem(atPath: child))?[.type] as? FileAttributeType == .typeDirectory {
                    pending.append(child)
                }
            }
        }
    }
}
