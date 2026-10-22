import Foundation
import LittleOrbitDomain

#if canImport(CryptoKit)
    import CryptoKit

    /// SHA-256 with CryptoKit, for backup checksums and ledger fingerprints. Format 1 isn't encrypted (D182).
    public struct CryptoKitBackupHashing: BackupHashing {
        public init() {}

        public func sha256Hex(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        public func makeDigest() -> any BackupDigest {
            CryptoKitBackupDigest()
        }
    }

    /// CryptoKit's incremental SHA-256.
    final class CryptoKitBackupDigest: BackupDigest {
        private var hasher = SHA256()

        func update(_ bytes: UnsafeRawBufferPointer) {
            hasher.update(bufferPointer: bytes)
        }

        func finish() -> String {
            hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }
#endif
