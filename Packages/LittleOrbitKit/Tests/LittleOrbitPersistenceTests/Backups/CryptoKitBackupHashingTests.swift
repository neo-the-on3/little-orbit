import Foundation
import Testing

@testable import LittleOrbitPersistence

#if canImport(CryptoKit)
    @Suite("CryptoKit backup hashing")
    struct CryptoKitBackupHashingTests {
        @Test("SHA-256 as lowercase hex")
        func knownValue() {
            #expect(
                CryptoKitBackupHashing().sha256Hex(Data("abc".utf8))
                    == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
            )
        }
    }
#endif
