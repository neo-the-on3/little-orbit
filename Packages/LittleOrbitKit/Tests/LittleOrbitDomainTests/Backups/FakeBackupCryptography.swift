import Foundation
import LittleOrbitDomain

/// A stand-in for CryptoKit so the codec runs on Linux. The hash is FNV-1a, and "sealing" prefixes a tag over
/// the password and the authenticated header, then reverses the bytes. Not cryptography; only the codec's rules
/// are under test.
struct FakeBackupCryptography: BackupCryptography {
    func sha256Hex(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    func makeEncryption() -> BackupEncryption {
        BackupEncryption(iterations: 600_000, salt: Data(repeating: 7, count: 16))
    }

    func seal(_ plaintext: Data, password: String, encryption: BackupEncryption, header: Data) throws -> Data {
        let tag = tag(password: password, header: header)
        return Data([UInt8(tag.count)]) + tag + Data(plaintext.reversed())
    }

    func open(_ sealed: Data, password: String, encryption: BackupEncryption, header: Data) throws -> Data {
        guard let length = sealed.first.map(Int.init), sealed.count > length else {
            throw BackupError.damaged
        }
        guard Data(sealed.dropFirst().prefix(length)) == tag(password: password, header: header) else {
            throw BackupError.incorrectPassword
        }
        return Data(sealed.dropFirst(1 + length).reversed())
    }

    private func tag(password: String, header: Data) -> Data {
        Data(sha256Hex(Data(password.precomposedStringWithCanonicalMapping.utf8) + header).utf8)
    }
}
