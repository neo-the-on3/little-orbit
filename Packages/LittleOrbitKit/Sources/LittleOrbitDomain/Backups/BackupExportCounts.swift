import Foundation
import Observation

/// How many exports of each backup are open now: from Export until the save panel closes. It's observable, so every window that shows a
/// backup follows it through `ExportBackupUseCase.exportCount(of:)` (D208.1).
@MainActor
@Observable
final class BackupExportCounts {
    private var counts: [UUID: Int] = [:]

    func count(of id: UUID) -> Int {
        counts[id] ?? 0
    }

    func begin(_ id: UUID) {
        counts[id, default: 0] += 1
    }

    func end(_ id: UUID) {
        let left = count(of: id) - 1
        counts[id] = left > 0 ? left : nil
    }
}
