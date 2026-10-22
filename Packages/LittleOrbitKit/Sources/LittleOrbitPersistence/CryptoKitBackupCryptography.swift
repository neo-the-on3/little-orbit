import Foundation
import LittleOrbitDomain

#if canImport(CryptoKit) && canImport(CommonCrypto)
    import CommonCrypto
    import CryptoKit

    /// SHA-256 checksums and export encryption with the system frameworks: a 256-bit key derived from the
    /// password with PBKDF2-HMAC-SHA256 and a random salt, then AES-GCM, all on the device (D63).
    public struct CryptoKitBackupCryptography: BackupCryptography {
        /// OWASP's 2023 guidance for PBKDF2-HMAC-SHA256.
        public static let defaultIterations = 600_000

        private let iterations: Int
        private let allowedIterations: ClosedRange<Int>

        /// Tests pass fewer iterations, and a matching `allowedIterations`, to run fast. Files record their own
        /// count; a count outside `allowedIterations` is refused as damaged before any key derivation.
        public init(
            iterations: Int = CryptoKitBackupCryptography.defaultIterations,
            allowedIterations: ClosedRange<Int> = BackupEncryption.allowedIterations,
        ) {
            self.iterations = iterations
            self.allowedIterations = allowedIterations
        }

        public func sha256Hex(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        public func makeEncryption() -> BackupEncryption {
            let salt = SymmetricKey(size: SymmetricKeySize(bitCount: 128)).withUnsafeBytes { Data($0) }
            return BackupEncryption(iterations: iterations, salt: salt)
        }

        public func seal(_ body: Data, password: String, encryption: BackupEncryption, header: Data) throws -> Data {
            let key = try key(password: password, encryption: encryption)
            guard let combined = try AES.GCM.seal(body, using: key, authenticating: header).combined else {
                throw BackupError.encryptionUnavailable
            }
            return combined
        }

        public func open(_ sealed: Data, password: String, encryption: BackupEncryption, header: Data) throws -> Data {
            let key = try key(password: password, encryption: encryption)
            do {
                return try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: header)
            } catch {
                throw BackupError.incorrectPassword
            }
        }

        /// PBKDF2-HMAC-SHA256 over the NFC-normalised password, so the same password typed on another keyboard
        /// or platform derives the same key. Unsupported parameters throw `damaged` before deriving anything.
        private func key(password: String, encryption: BackupEncryption) throws -> SymmetricKey {
            guard encryption.isSupported(allowedIterations: allowedIterations),
                let rounds = UInt32(exactly: encryption.iterations)
            else {
                throw BackupError.damaged
            }
            let passwordBytes = Array(password.precomposedStringWithCanonicalMapping.utf8)
            let salt = Array(encryption.salt)
            var derived = [UInt8](repeating: 0, count: 32)
            let status = passwordBytes.withUnsafeBufferPointer { passwordBuffer in
                passwordBuffer.withMemoryRebound(to: Int8.self) { passwordChars in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordChars.baseAddress,
                        passwordBytes.count,
                        salt,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        rounds,
                        &derived,
                        derived.count,
                    )
                }
            }
            guard status == kCCSuccess else {
                throw BackupError.encryptionUnavailable
            }
            return SymmetricKey(data: derived)
        }
    }
#endif
