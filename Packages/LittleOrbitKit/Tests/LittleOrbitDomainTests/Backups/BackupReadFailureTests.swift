import Foundation
import Testing

@testable import LittleOrbitDomain

/// An archive reader whose pass number `failingPass` (1 is the manifest pass, 2 the checksum pass, 3 the restore's
/// own pass) throws `error` instead of reading, as a file evicted from iCloud Drive mid-read would.
private final class FailingArchiving: BackupArchiving, @unchecked Sendable {
    let base = SpyArchiving()
    private let failingPass: Int
    private let error: any Error
    private var passes = 0

    init(failingPass: Int, error: any Error) {
        self.failingPass = failingPass
        self.error = error
    }

    func archive(_ files: BackupSnapshotFiles) throws -> Data {
        try base.archive(files)
    }

    func entries(
        of archive: BackupArchiveSource,
        reading: (String) -> BackupArchiveRead,
    ) throws -> [BackupArchiveEntry] {
        passes += 1
        if passes == failingPass {
            throw error
        }
        return try base.entries(of: archive, reading: reading)
    }
}

private struct UnexpectedError: Error {}

/// D207.2: every read or I/O error while a picked file is checked or restored is `unreadableFile`; only a file that
/// was read and fails the manifest, safety or checksum checks is `damaged`; anything else is passed on as it is.
@Suite("Backup import read failures (D207.2)", .timeLimit(.minutes(2)))
struct BackupReadFailureTests {
    private let codec = BackupCodec(hashing: FakeBackupHashing())

    private func files() throws -> BackupSnapshotFiles {
        let ledger = LedgerSnapshot(accounts: [
            Account(name: "Everyday Savings", type: .savings, currencyCode: "EUR", openingBalance: 100, sortOrder: 1)
        ])
        let manifest = BackupManifest(
            kind: .manual,
            createdAt: Date(timeIntervalSince1970: 1_792_640_525),
            nameIndex: 1,
            schemaVersion: "1.0.0",
            accountCount: 1,
            transactionCount: 0,
            attachmentCount: 0,
            month: "2026-10",
        )
        return try codec.encode(BackupContents(manifest: manifest, ledger: ledger))
    }

    static let readErrors: [any Error & Sendable] = [
        CocoaError(.fileReadUnknown),
        CocoaError(.fileReadNoPermission),
        CocoaError(.fileNoSuchFile),
        CocoaError(.ubiquitousFileUnavailable),
        POSIXError(.EIO),
        NSError(domain: NSPOSIXErrorDomain, code: Int(EIO)),
    ]

    @Test("A read error when the file is opened is unreadable", arguments: readErrors.indices)
    func failedOpen(index: Int) throws {
        let archiving = FailingArchiving(failingPass: 1, error: Self.readErrors[index])
        let data = try archiving.archive(files())
        #expect(throws: BackupError.unreadableFile) {
            try BackupArchiveImport(archiving: archiving, codec: codec).check(.data(data))
        }
    }

    @Test("A read error partway through, in the checksum pass or the restore's pass, is unreadable")
    func midStream() throws {
        for pass in [2, 3] {
            let archiving = FailingArchiving(failingPass: pass, error: POSIXError(.EIO))
            let data = try archiving.archive(files())
            #expect(throws: BackupError.unreadableFile) {
                try BackupArchiveImport(archiving: archiving, codec: codec).contents(of: .data(data))
            }
        }
    }

    @Test("A file that was read but fails its checksum is still damaged")
    func checksumMismatch() throws {
        var changed = try files()
        changed["shared.json"]?[0] ^= 1
        let archiving = FailingArchiving(failingPass: 0, error: UnexpectedError())
        let data = try archiving.archive(changed)
        #expect(throws: BackupError.damaged) {
            try BackupArchiveImport(archiving: archiving, codec: codec).check(.data(data))
        }
    }

    @Test("Damaged and newer-format results from the reader stay as they are")
    func backupErrorsPassThrough() throws {
        for error in [BackupError.damaged, .newerFormat] {
            let archiving = FailingArchiving(failingPass: 2, error: error)
            let data = try archiving.archive(files())
            #expect(throws: error) { try BackupArchiveImport(archiving: archiving, codec: codec).check(.data(data)) }
        }
    }

    @Test("An unexpected error isn't called unreadable or damaged")
    func unexpected() throws {
        let archiving = FailingArchiving(failingPass: 2, error: UnexpectedError())
        let data = try archiving.archive(files())
        #expect(throws: UnexpectedError.self) {
            try BackupArchiveImport(archiving: archiving, codec: codec).check(.data(data))
        }
        #expect(!BackupReadFailure.isReadFailure(UnexpectedError()))
        #expect(!BackupReadFailure.isReadFailure(CocoaError(.fileWriteOutOfSpace)))
    }

    @Test("A write or permission code counts only when the store raised it reading a stored backup's file")
    func writeCodesOnlyFromStoredReads() {
        for code in [CocoaError.Code.fileWriteNoPermission, .fileWriteVolumeReadOnly] {
            #expect(!BackupReadFailure.isReadFailure(CocoaError(code)))
            #expect(BackupReadFailure.isReadFailure(BackupFileReadError(CocoaError(code))))
        }
        let wrapped = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.Code.fileWriteNoPermission.rawValue,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))],
        )
        #expect(!BackupReadFailure.isReadFailure(wrapped))
    }
}
