import Foundation
import LittleOrbitDomain

/// Folder names by date and time (D209).
extension FileBackupStorage {
    /// Moves a finished folder into the Backups folder under `yyyy-MM-dd-HH-mm`, from the manifest's `createdAt`
    /// in the device's time zone, or `-2`, `-3` and so on when that name is taken. A name that's in use, or turns
    /// out to be at the move, is never reused or overwritten.
    func moveIntoPlace(_ temporary: URL, id: UUID, manifest: Data?) throws {
        let base = manifest.flatMap(BackupFolderNames.createdAt)
            .map { BackupFolderNames.base(for: $0, in: timeZone()) }
        guard let base else {
            try moveFolder(temporary, named: id.uuidString, id: id)
            return
        }
        for suffix in 1...10_000 {
            let name = suffix == 1 ? base : "\(base)-\(suffix)"
            if fileManager.fileExists(atPath: folder.appendingPathComponent(name).path) {
                continue
            }
            do {
                try moveFolder(temporary, named: name, id: id)
                return
            } catch let error where fileManager.fileExists(atPath: folder.appendingPathComponent(name).path) {
                // Taken between the check and the move: try the next one.
                _ = error
                continue
            }
        }
        try moveFolder(temporary, named: id.uuidString, id: id)
    }

    private func moveFolder(_ temporary: URL, named name: String, id: UUID) throws {
        try fileManager.moveItem(at: temporary, to: folder.appendingPathComponent(name, isDirectory: true))
        names.set(name, for: id)
    }
}

/// Each backup's folder name by its ID, and how a folder's ID is found. Thread-safe.
final class BackupFolderNames: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [UUID: String] = [:]

    func name(of id: UUID) -> String? {
        lock.withLock { names[id] }
    }

    func set(_ name: String, for id: UUID) {
        lock.withLock { names[id] = name }
    }

    func remove(_ id: UUID) {
        lock.withLock { _ = names.removeValue(forKey: id) }
    }

    func byName() -> [String: UUID] {
        lock.withLock { Dictionary(names.map { ($1, $0) }, uniquingKeysWith: { first, _ in first }) }
    }

    func replace(with found: [UUID: String]) {
        lock.withLock { names = found }
    }

    /// `yyyy-MM-dd-HH-mm` in `timeZone`, Gregorian and `en_US_POSIX`, so it's 24-hour and zero-padded whatever the
    /// user's settings (D209).
    static func base(for date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HH-mm"
        return formatter.string(from: date)
    }

    /// The manifest's `backup.createdAt`, for naming a folder that's being written.
    static func createdAt(in manifest: Data) -> Date? {
        (try? decoder.decode(ManifestHead.self, from: manifest))?.backup.createdAt
    }

    /// The manifest's `backup.id`, or `nil` when there's no readable manifest or no ID in it.
    static func manifestID(in folder: URL) -> UUID? {
        let url = folder.appendingPathComponent(BackupFormat.manifestPath)
        // A manifest that's a symlink is never read through (B1).
        guard (try? FileBackupStorage.entryType(at: url)) == .typeRegular, let data = try? Data(contentsOf: url) else {
            return nil
        }
        return (try? decoder.decode(ManifestHead.self, from: data))?.backup.id
    }

    /// A stable ID made from a folder's name, for a folder whose manifest has none. The same name always gives the
    /// same ID, so the list, the status cache and Delete agree.
    static func id(for name: String) -> UUID {
        var first: UInt64 = 0xcbf2_9ce4_8422_2325
        var second: UInt64 = 0x8422_2325_cbf2_9ce4
        for byte in name.utf8 {
            first = (first ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            second = (second ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 &+ 1
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: first >> (8 * index))
            bytes[index + 8] = UInt8(truncatingIfNeeded: second >> (8 * index))
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15],
            )
        )
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    private struct ManifestHead: Decodable {
        var backup: ManifestHeadBackup
    }
}

/// The two fields of a manifest's `backup` that a folder's name and identity need.
private struct ManifestHeadBackup: Decodable {
    var id: UUID?
    var createdAt: Date?
}
