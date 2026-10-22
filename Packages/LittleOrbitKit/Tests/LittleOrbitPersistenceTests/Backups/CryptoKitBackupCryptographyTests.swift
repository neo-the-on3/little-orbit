#if canImport(CryptoKit) && canImport(CommonCrypto)
    import Foundation
    import LittleOrbitDomain
    import LittleOrbitPersistence
    import Testing

    /// D63: AES-256-GCM with a PBKDF2-HMAC-SHA256 key. A low iteration count keeps the tests fast.
    @Suite("CryptoKit backup cryptography")
    struct CryptoKitBackupCryptographyTests {
        private let fast = 1_000...10_000_000
        private var cryptography: CryptoKitBackupCryptography {
            CryptoKitBackupCryptography(iterations: 1_000, allowedIterations: fast)
        }

        private let header = Data(#"{"format":"little-orbit-backup","formatVersion":1}"#.utf8)

        @Test("SHA-256 matches the known value")
        func sha256() {
            #expect(
                cryptography.sha256Hex(Data("abc".utf8))
                    == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
            )
        }

        @Test("Seal and open round-trip; a wrong password is rejected")
        func sealOpen() throws {
            let plaintext = Data("ledger".utf8)
            let encryption = cryptography.makeEncryption()
            #expect(encryption.iterations == 1_000)
            #expect(encryption.salt.count == 16)
            let sealed = try cryptography.seal(
                plaintext,
                password: "orbit🔒पासवर्ड",
                encryption: encryption,
                header: header,
            )
            #expect(sealed != plaintext)
            #expect(
                try cryptography.open(sealed, password: "orbit🔒पासवर्ड", encryption: encryption, header: header)
                    == plaintext
            )
            #expect(throws: BackupError.incorrectPassword) {
                try cryptography.open(sealed, password: "orbit", encryption: encryption, header: header)
            }
        }

        @Test("The header is authenticated: a changed header fails to open (B2)")
        func associatedData() throws {
            let encryption = cryptography.makeEncryption()
            let sealed = try cryptography.seal(
                Data("ledger".utf8),
                password: "password",
                encryption: encryption,
                header: header,
            )
            let changed = Data(#"{"format":"little-orbit-backup","formatVersion":2}"#.utf8)
            #expect(throws: BackupError.incorrectPassword) {
                try cryptography.open(sealed, password: "password", encryption: encryption, header: changed)
            }
        }

        @Test(
            "Iteration counts outside the allowed range are damaged, never a trap (B2)",
            arguments: [0, -5, 99_999, 10_000_001, Int(UInt32.max) + 1, Int.max],
        )
        func iterationBounds(iterations: Int) {
            let production = CryptoKitBackupCryptography()
            let encryption = BackupEncryption(iterations: iterations, salt: Data(repeating: 1, count: 16))
            #expect(throws: BackupError.damaged) {
                try production.open(
                    Data(repeating: 0, count: 40),
                    password: "password",
                    encryption: encryption,
                    header: header,
                )
            }
        }

        @Test("Unknown algorithms are damaged (B2)")
        func unknownAlgorithm() {
            let encryption = BackupEncryption(
                algorithm: "ChaCha20-Poly1305",
                iterations: 1_000,
                salt: Data(repeating: 1, count: 16),
            )
            #expect(throws: BackupError.damaged) {
                try cryptography.open(
                    Data(repeating: 0, count: 40),
                    password: "password",
                    encryption: encryption,
                    header: header,
                )
            }
        }

        @Test("Composed and decomposed forms of a password derive the same key (NFC, B2)")
        func normalisation() throws {
            let encryption = cryptography.makeEncryption()
            let sealed = try cryptography.seal(
                Data("ledger".utf8),
                password: "cafe\u{301}",
                encryption: encryption,
                header: header,
            )
            #expect(
                try cryptography.open(sealed, password: "caf\u{E9}", encryption: encryption, header: header)
                    == Data("ledger".utf8)
            )
        }

        @Test("Each export gets a fresh salt")
        func freshSalt() {
            #expect(cryptography.makeEncryption().salt != cryptography.makeEncryption().salt)
        }

        @Test("The default is 600,000 iterations, inside the allowed range")
        func defaults() {
            #expect(CryptoKitBackupCryptography.defaultIterations == 600_000)
            #expect(BackupEncryption.allowedIterations.contains(CryptoKitBackupCryptography.defaultIterations))
        }

        @Test("An encrypted backup file opens only with its password")
        func codec() throws {
            let codec = BackupCodec(cryptography: cryptography, allowedIterations: fast)
            let manifest = BackupManifest(
                kind: .manual,
                createdAt: Date(timeIntervalSince1970: 1_792_640_525),
                nameIndex: 1,
                schemaVersion: "1.0.0",
                accountCount: 0,
                transactionCount: 0,
                attachmentCount: 0,
            )
            let contents = BackupContents(manifest: manifest, ledger: LedgerSnapshot())
            let data = try codec.encode(contents, password: "long password")
            #expect(throws: BackupError.passwordRequired) { try codec.decode(data) }
            #expect(throws: BackupError.incorrectPassword) { try codec.decode(data, password: "other password") }
            #expect(try codec.decode(data, password: "long password") == contents)
        }
    }
#endif
