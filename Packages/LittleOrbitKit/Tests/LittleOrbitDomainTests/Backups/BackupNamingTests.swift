import Foundation
import LittleOrbitDomain
import Testing

/// D173.11 and D174: the name index fixed when a backup is made. The file name itself is formatted in Features.
@Suite("Backup naming")
struct BackupNamingTests {
    /// 2026-10-22 09:12:05 IST.
    private let morning = Date(timeIntervalSince1970: 1_792_640_525)

    @Test("A second backup in the same minute gets index 2, a third 3 (D173.11, S71)")
    func suffix() {
        let first = BackupRecord(kind: .automatic, createdAt: morning, nameIndex: 1)
        let secondIndex = BackupNaming.nameIndex(for: morning.addingTimeInterval(10), existing: [first])
        #expect(secondIndex == 2)
        let second = BackupRecord(kind: .manual, createdAt: morning.addingTimeInterval(10), nameIndex: secondIndex)
        #expect(BackupNaming.nameIndex(for: morning.addingTimeInterval(20), existing: [first, second]) == 3)
    }

    @Test("A different minute starts again at the plain name")
    func nextMinute() {
        let first = BackupRecord(kind: .manual, createdAt: morning, nameIndex: 1)
        #expect(BackupNaming.nameIndex(for: morning.addingTimeInterval(60), existing: [first]) == 1)
    }

    @Test("The lowest free index is used after a delete, and nothing is renamed (D174, S73, S77)")
    func lowestFree() {
        let first = BackupRecord(kind: .manual, createdAt: morning, nameIndex: 1)
        let third = BackupRecord(kind: .manual, createdAt: morning.addingTimeInterval(20), nameIndex: 3)
        #expect(BackupNaming.nameIndex(for: morning.addingTimeInterval(30), existing: [first, third]) == 2)
        #expect(BackupNaming.nameIndex(for: morning.addingTimeInterval(30), existing: [third]) == 1)
    }

    @Test("Same-minute indexes are counted in UTC minutes, so a half-hour zone changes nothing (S76)")
    func utcMinutes() {
        #expect(BackupNaming.minuteNumber(morning) == BackupNaming.minuteNumber(morning.addingTimeInterval(5)))
        #expect(BackupNaming.minuteNumber(morning) != BackupNaming.minuteNumber(morning.addingTimeInterval(60)))
    }
}
