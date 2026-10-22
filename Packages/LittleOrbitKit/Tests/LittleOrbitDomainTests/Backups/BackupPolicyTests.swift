import Foundation
import LittleOrbitDomain
import Testing

/// D62, D96.3, D116.3, D118.1 and D118.2: when an automatic backup is made and which are kept.
@Suite("Backup policy")
struct BackupPolicyTests {
    private let zone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
    /// 2026-10-22 09:12:05 IST.
    private let now = Date(timeIntervalSince1970: 1_792_640_525)
    private let day: TimeInterval = 86_400

    private func needs(_ catalog: BackupCatalog, fingerprint: String = "now", empty: Bool = false) -> Bool {
        BackupPolicy.needsAutomaticBackup(
            now: now,
            timeZone: zone,
            catalog: catalog,
            currentFingerprint: fingerprint,
            ledgerIsEmpty: empty,
        )
    }

    @Test("Changed data with no backup today gets one (S1)")
    func firstOfTheDay() {
        let yesterday = BackupRecord(kind: .automatic, createdAt: now - day, fingerprint: "old")
        #expect(needs(BackupCatalog(records: [yesterday])))
    }

    @Test("At most one automatic backup per local day (S2)")
    func oncePerDay() {
        let earlier = BackupRecord(kind: .automatic, createdAt: now - 3_600, fingerprint: "old")
        #expect(!needs(BackupCatalog(records: [earlier])))
    }

    @Test("The day is the device's local day: 00:30 IST is a new day after 23:30 IST")
    func localDay() {
        let lateNight = Date(timeIntervalSince1970: 1_792_605_600)  // 2026-10-21 23:30 IST
        let afterMidnight = lateNight + 3_600
        let catalog = BackupCatalog(records: [BackupRecord(kind: .automatic, createdAt: lateNight)])
        #expect(!BackupPolicy.hasAutomaticBackup(on: afterMidnight, timeZone: zone, in: catalog))
        #expect(BackupPolicy.hasAutomaticBackup(on: lateNight + 600, timeZone: zone, in: catalog))
    }

    @Test("A manual or Before restore backup isn't the day's automatic one (S3)")
    func manualDoesNotCount() {
        let manual = BackupRecord(kind: .manual, createdAt: now - 3_600, fingerprint: "old")
        let before = BackupRecord(kind: .beforeRestore, createdAt: now - 1_800, fingerprint: "older")
        #expect(needs(BackupCatalog(records: [manual, before])))
    }

    @Test("No automatic backup when the newest backup already reflects the data (S4, S47, D116.3)")
    func unchanged() {
        let manual = BackupRecord(kind: .manual, createdAt: now - 3_600, fingerprint: "now")
        #expect(!needs(BackupCatalog(records: [manual])))
    }

    @Test("Deleting the newest backup makes the next one compare with what's left (S48, D118.1)")
    func newestRemaining() {
        let older = BackupRecord(kind: .automatic, createdAt: now - 2 * day, fingerprint: "old")
        #expect(needs(BackupCatalog(records: [older])))
    }

    @Test("No automatic backup right after a restore until the data changes (S53, D96.3, D118.2)")
    func afterRestore() {
        let before = BackupRecord(kind: .beforeRestore, createdAt: now - 60, fingerprint: "previous")
        let catalog = BackupCatalog(records: [before], restoredFingerprint: "now")
        #expect(!needs(catalog))
        #expect(needs(catalog, fingerprint: "edited"))
    }

    @Test("Default categories alone are an empty ledger; an account isn't (D179.3)")
    func emptyDefinition() {
        let categories = LedgerBook.seedDefaultCategories(in: LedgerSnapshot(), now: now)
        #expect(!categories.categories.isEmpty)
        #expect(BackupPolicy.isEmpty(categories))
        let account = Account(name: "Wallet", type: .cash, currencyCode: "INR", openingBalance: 0)
        #expect(!BackupPolicy.isEmpty(LedgerSnapshot(accounts: [account])))
    }

    @Test("A new, empty ledger with no backups makes none (D179.3)")
    func emptyLedger() {
        #expect(!needs(BackupCatalog(), empty: true))
        #expect(needs(BackupCatalog(), empty: false))
    }

    @Test("The list is newest first, all kinds together (S70)")
    func newestFirst() {
        let old = BackupRecord(kind: .manual, createdAt: now - day)
        let new = BackupRecord(kind: .automatic, createdAt: now)
        let middle = BackupRecord(kind: .beforeRestore, createdAt: now - 60)
        #expect(BackupCatalog(records: [old, new, middle]).newestFirst.map(\.id) == [new.id, middle.id, old.id])
    }

    @Test("The list sorts by the stored time, not the name, across a time-zone change (D179.4)")
    func sortsByStoredTime() {
        // Made at 09:12 IST, then 30 minutes later in London, where the name would read 05:12.
        let first = BackupRecord(kind: .manual, createdAt: now, nameIndex: 1)
        let later = BackupRecord(kind: .manual, createdAt: now + 1_800, nameIndex: 1)
        #expect(BackupCatalog(records: [first, later]).newestFirst.map(\.id) == [later.id, first.id])
    }
}
