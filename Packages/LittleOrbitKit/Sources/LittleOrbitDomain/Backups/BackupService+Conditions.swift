import Foundation

/// Checking backups in full, and remembering what each check found (D196.3).
extension BackupService {
    /// `check`'s result, with the backup's condition remembered: a damaged backup shows as 'Damaged' from then on
    /// (D196.3).
    nonisolated static func remembering<Value>(
        _ id: UUID,
        storage: any BackupStorage,
        check: () throws -> Value,
    ) throws -> Value {
        do {
            let value = try check()
            remember([id: .restorable], storage: storage)
            return value
        } catch BackupError.damaged {
            remember([id: .damaged], storage: storage)
            throw BackupError.damaged
        }
    }

    /// `records` with each one that isn't of a newer format read and checked in full. A folder gone meanwhile drops
    /// out; any other read error is thrown.
    nonisolated static func checkedInFull(
        _ records: [BackupRecord],
        storage: any BackupStorage,
        codec: BackupCodec,
    ) throws -> [BackupRecord] {
        var checked: [BackupRecord] = []
        var conditions: [UUID: BackupCondition] = [:]
        for var record in records {
            if record.condition != .newerFormat {
                do {
                    _ = try codec.verify(storage.files(id: record.id))
                    record.condition = .restorable
                } catch BackupError.damaged {
                    record.condition = .damaged
                } catch BackupError.newerFormat {
                    record.condition = .newerFormat
                } catch BackupError.notFound {
                    continue
                }
                conditions[record.id] = record.condition
            }
            checked.append(record)
        }
        remember(conditions, storage: storage)
        return checked
    }

    /// Updates the cached condition of known backups. Losing this only loses the 'Damaged' mark until the next
    /// check, so a failed save is ignored.
    nonisolated static func remember(_ conditions: [UUID: BackupCondition], storage: any BackupStorage) {
        guard var status = try? storage.loadStatus() else {
            return
        }
        var changed = false
        for (id, condition) in conditions {
            if var record = status.known[id], record.condition != condition {
                record.condition = condition
                status.known[id] = record
                changed = true
            }
        }
        if changed {
            try? storage.saveStatus(status)
        }
    }
}
