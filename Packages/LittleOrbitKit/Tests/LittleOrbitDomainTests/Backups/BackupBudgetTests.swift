import Foundation
import LittleOrbitDomain
import Testing

/// Budgets in backups (#25, D294): they fill format 1's reserved budgets section, and backups made before budgets
/// still read.
@Suite("Budgets in backups (#25)")
struct BackupBudgetTests {
    private let codec = BackupCodec(hashing: FakeBackupHashing())
    private let created: Date
    private let food: TransactionCategory

    private let budget: Budget

    init() {
        let created = Date(timeIntervalSince1970: 1_792_640_525)
        let food = TransactionCategory(name: "Food")
        self.created = created
        self.food = food
        var budget = Budget(
            name: "Eating out",
            currencyCode: "INR",
            categoryIDs: [food.id],
            startDay: CalendarDay(year: 2027, month: 1, day: 31),
            recurrence: .custom(every: 3, unit: .week),
            limit: Decimal(string: "8000.50")!,
            carriesOverUnspent: true,
            createdAt: created,
        )
        budget.limits.append(
            BudgetLimit(startDay: CalendarDay(year: 2027, month: 3, day: 14), amount: 9_000, createdAt: created)
        )
        self.budget = budget
    }

    private func contents(_ ledger: LedgerSnapshot) -> BackupContents {
        let manifest = BackupManifest(
            kind: .manual,
            createdAt: created,
            nameIndex: 1,
            schemaVersion: "1.0.0",
            accountCount: 0,
            transactionCount: 0,
            attachmentCount: 0,
        )
        return BackupContents(manifest: manifest, ledger: ledger)
    }

    @Test("Budgets round-trip with their repeat, carry-over and limit history, and the manifest lists them")
    func roundTrip() throws {
        let original = contents(LedgerSnapshot(categories: [food], budgets: [budget]))
        #expect(original.manifest.sections == BackupSection.populated + [.budgets])
        let decoded = try codec.decode(codec.encode(original))
        #expect(decoded == original)
        #expect(decoded.ledger.budgets == [budget])
        #expect(decoded.manifest.sections.contains(.budgets))
    }

    @Test("Format 1 stays: a backup without budgets is written as before and reads back with none")
    func withoutBudgets() throws {
        let original = contents(LedgerSnapshot(categories: [food]))
        #expect(original.manifest.formatVersion == 1)
        #expect(original.manifest.sections == BackupSection.populated)
        let files = try codec.encode(original)
        let shared = try #require(files[BackupFormat.sharedPath])
        let object = try #require(try JSONSerialization.jsonObject(with: shared) as? [String: Any])
        #expect((object["budgets"] as? [Any])?.isEmpty == true)
        #expect(try codec.decode(files).ledger.budgets.isEmpty)
    }

    @Test("A ledger without budgets keeps the fingerprint it had before budgets; adding one changes it")
    func fingerprint() throws {
        let ledger = LedgerSnapshot(categories: [food])
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as? [String: Any]
        #expect(encoded?["budgets"] == nil)
        var withBudget = ledger
        withBudget.budgets = [budget]
        #expect(try codec.fingerprint(of: ledger) != codec.fingerprint(of: withBudget))
    }

    @Test("Q9 (b): a ledger without budgets fingerprints to the value `main` gave it at 1f27b72")
    func pinnedFingerprint() throws {
        // Written by 1f27b72's codec with this fake hashing. A change means format 1 changed (#174 B2).
        #expect(try codec.fingerprint(of: FormatOneSample.ledger) == "9d714c20d6f373d8")
    }

    @Test(
        "B1, delta NB1: a bad category, limit or repeat, or a repeated category or limit day makes a backup damaged",
        arguments: [
            "missing category", "income category", "zero limit", "negative limit", "repeat of 0", "unknown repeat",
            "category twice", "two limits on one day",
        ],
    )
    func damagedBudgets(_ damage: String) throws {
        let salary = TransactionCategory(name: "Salary", kind: .income)
        var broken = budget
        switch damage {
        case "missing category": broken.categoryIDs = [UUID()]
        case "income category": broken.categoryIDs = [salary.id]
        case "zero limit": broken.limits[0].amount = 0
        case "negative limit": broken.limits[0].amount = -1
        case "repeat of 0": broken.recurrence = .custom(every: 0, unit: .week)
        case "category twice": broken.categoryIDs = [food.id, food.id]
        case "two limits on one day":
            broken.limits.append(
                BudgetLimit(startDay: broken.limits[0].startDay, amount: 1, createdAt: broken.createdAt)
            )
        default: break
        }
        var files = try codec.encode(contents(LedgerSnapshot(categories: [food, salary], budgets: [broken])))
        if damage == "unknown repeat" {
            let shared = try #require(files[BackupFormat.sharedPath])
            let text = try #require(String(bytes: shared, encoding: .utf8))
            files[BackupFormat.sharedPath] = Data(
                text.replacingOccurrences(of: #""custom""#, with: #""hourly""#).utf8
            )
            files = try rehashed(files)
        }
        #expect(throws: BackupError.damaged) { try codec.decode(files) }
        #expect(throws: BackupError.damaged) { try codec.decodeDetails(files) }
    }

    @Test("B1: a budget with no categories left restores, as a category delete leaves it (D307.5)")
    func budgetWithNoCategories() throws {
        var empty = budget
        empty.categoryIDs = []
        let original = contents(LedgerSnapshot(categories: [food], budgets: [empty]))
        #expect(try codec.decode(codec.encode(original)).ledger.budgets == [empty])
    }

    /// `files` with its manifest's size and checksum for each file worked out again, as an edited backup would have.
    private func rehashed(_ files: BackupSnapshotFiles) throws -> BackupSnapshotFiles {
        var files = files
        let manifest = try #require(files[BackupFormat.manifestPath])
        var object = try #require(try JSONSerialization.jsonObject(with: manifest) as? [String: Any])
        var listed = try #require(object["files"] as? [String: [String: Any]])
        let hashing = FakeBackupHashing()
        for path in listed.keys {
            let data = try #require(files[path])
            listed[path] = ["sha256": hashing.sha256Hex(data), "byteSize": data.count]
        }
        object["files"] = listed
        files[BackupFormat.manifestPath] = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return files
    }
}
