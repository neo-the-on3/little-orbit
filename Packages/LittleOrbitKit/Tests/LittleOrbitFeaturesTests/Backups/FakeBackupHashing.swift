import Foundation
import LittleOrbitDomain

/// A stand-in for CryptoKit's SHA-256 so the codec runs on Linux: FNV-1a, as hex. Only the codec's rules are
/// under test.
struct FakeBackupHashing: BackupHashing {
    func sha256Hex(_ data: Data) -> String {
        let digest = FakeBackupDigest()
        data.withUnsafeBytes { digest.update($0) }
        return digest.finish()
    }

    func makeDigest() -> any BackupDigest {
        FakeBackupDigest()
    }
}

/// FNV-1a, a chunk at a time: the same hex as hashing the bytes in one go.
final class FakeBackupDigest: BackupDigest {
    private var hash: UInt64 = 0xcbf2_9ce4_8422_2325

    func update(_ bytes: UnsafeRawBufferPointer) {
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
    }

    func finish() -> String {
        String(hash, radix: 16)
    }
}
