import Foundation
import LittleOrbitDomain
import Testing

/// D63, D96.1, D116.4 and D118.4: the `.littleorbit-backup` file.
@Suite("Backup codec")
struct BackupCodecTests {
    private let codec = BackupCodec(cryptography: FakeBackupCryptography())
    private let created = Date(timeIntervalSince1970: 1_792_640_525.123_456)

    private func contents() -> BackupContents {
        let dinar = Account(
            name: "Kuwait Account",
            type: .savings,
            currencyCode: "KWD",
            openingBalance: Decimal(string: "1.234", locale: Locale(identifier: "en_US_POSIX")) ?? 0,
            sortOrder: 1,
        )
        let cash = Account(name: "Wallet", type: .cash, currencyCode: "INR", openingBalance: 500, sortOrder: 2)
        let spend = Transaction(amount: 120, date: created, accountID: cash.id, createdAt: created)
        let ledger = LedgerSnapshot(accounts: [dinar, cash], transactions: [spend])
        let manifest = BackupManifest(
            kind: .manual,
            createdAt: created,
            nameIndex: 1,
            schemaVersion: "1.0.0",
            accountCount: 2,
            transactionCount: 1,
            attachmentCount: 0,
        )
        return BackupContents(manifest: manifest, ledger: ledger)
    }

    @Test("A backup round-trips exactly, including KWD 1.234 and sub-second dates")
    func roundTrip() throws {
        let original = contents()
        let decoded = try codec.decode(codec.encode(original))
        #expect(decoded == original)
        #expect(decoded.accounts.first { $0.currencyCode == "KWD" }?.openingBalance.description == "1.234")
        #expect(decoded.manifest.createdAt == created)
    }

    @Test("Reserved sections are written empty and listed as not yet populated")
    func reservedSections() throws {
        let data = try codec.encode(contents())
        let decoded = try codec.decode(data)
        #expect(decoded.importRules.isEmpty)
        #expect(decoded.budgets.isEmpty)
        #expect(decoded.scheduledItems.isEmpty)
        #expect(decoded.reconciliationHistory.isEmpty)
        #expect(decoded.manifest.sections == BackupSection.populated)
        #expect(!BackupSection.populated.contains(.budgets))
    }

    @Test("An encrypted backup needs its password, and a wrong one can be retried (S49, D118.4)")
    func encrypted() throws {
        let original = contents()
        let data = try codec.encode(original, password: "orbit🔒पासवर्ड")
        #expect(try codec.isEncrypted(data))
        #expect(throws: BackupError.passwordRequired) { try codec.decode(data) }
        #expect(throws: BackupError.incorrectPassword) { try codec.decode(data, password: "wrong-password") }
        #expect(throws: BackupError.incorrectPassword) { try codec.decode(data, password: "still-wrong") }
        #expect(try codec.decode(data, password: "orbit🔒पासवर्ड") == original)
    }

    @Test("An unencrypted backup isn't reported as encrypted")
    func plain() throws {
        #expect(try !codec.isEncrypted(codec.encode(contents())))
    }

    @Test(
        "Files that aren't backups are damaged (S50)",
        arguments: [
            Data(),
            Data("Shopping list: milk, eggs".utf8),
            Data(#"{"format":"something-else","formatVersion":1}"#.utf8),
            Data([0xFF, 0xD8, 0xFF, 0xE0]),
        ],
    )
    func notABackup(data: Data) {
        #expect(throws: BackupError.damaged) { try codec.decode(data) }
    }

    @Test("A truncated backup is damaged")
    func truncated() throws {
        let data = try codec.encode(contents())
        #expect(throws: BackupError.damaged) { try codec.decode(data.prefix(data.count / 2)) }
    }

    @Test("A changed body fails its checksum and is damaged")
    func tampered() throws {
        let data = try codec.encode(contents())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["body"] = Data("{}".utf8).base64EncodedString()
        let changed = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: BackupError.damaged) { try codec.decode(changed) }
    }

    @Test("A newer format asks for an update, before anything else is checked (S52)")
    func newerFormat() throws {
        let data = try codec.encode(contents())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["formatVersion"] = BackupFormat.currentVersion + 1
        object["checksum"] = "not-checked"
        let newer = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: BackupError.newerFormat) { try codec.decode(newer) }
    }

    @Test("The fingerprint ignores record order and backup metadata (D116.3)")
    func fingerprint() throws {
        let ledger = contents().ledger
        var reversed = ledger
        reversed.accounts.reverse()
        #expect(try codec.fingerprint(of: ledger) == codec.fingerprint(of: reversed))
        var changed = ledger
        changed.accounts[0].name = "Renamed"
        #expect(try codec.fingerprint(of: ledger) != codec.fingerprint(of: changed))
    }

    private func rewrite(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func rewriteEncryption(_ data: Data, _ key: String, _ value: Any) throws -> Data {
        try rewrite(data) { object in
            var encryption = object["encryption"] as? [String: Any] ?? [:]
            encryption[key] = value
            object["encryption"] = encryption
        }
    }

    @Test(
        "Encryption parameters outside what format 1 supports are damaged, not a crash (B2)",
        arguments: [
            ("iterations", "99999"),
            ("iterations", "10000001"),
            ("iterations", "5000000000"),
            ("iterations", "-1"),
            ("algorithm", "ChaCha20-Poly1305"),
            ("keyDerivation", "scrypt"),
        ],
    )
    func unsupportedParameters(key: String, value: String) throws {
        let data = try codec.encode(contents(), password: "long password")
        let crafted = try rewriteEncryption(data, key, Int(value).map { $0 as Any } ?? value)
        #expect(throws: BackupError.damaged) { try codec.decode(crafted, password: "long password") }
    }

    @Test("A changed header fails to open even with the right password (B2, associated data)")
    func headerIsAuthenticated() throws {
        let data = try codec.encode(contents(), password: "long password")
        // Still in range, so only the authenticated header catches it.
        let crafted = try rewriteEncryption(data, "iterations", 600_001)
        #expect(throws: BackupError.incorrectPassword) { try codec.decode(crafted, password: "long password") }
    }

    @Test("A password typed composed or decomposed opens the same file (NFC)")
    func normalisedPassword() throws {
        let composed = "caf\u{E9} पासवर्ड"
        let decomposed = "cafe\u{301} पासवर्ड"
        #expect(Array(composed.utf8) != Array(decomposed.utf8))
        let original = contents()
        let data = try codec.encode(original, password: decomposed)
        #expect(try codec.decode(data, password: composed) == original)
    }
}
