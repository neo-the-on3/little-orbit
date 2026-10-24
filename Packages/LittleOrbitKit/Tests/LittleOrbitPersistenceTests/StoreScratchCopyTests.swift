import Foundation
import Testing

@testable import LittleOrbitPersistence

/// P2: the probe's scratch copy never tears, and leftovers from a crashed probe are removed.
@Suite("Store scratch copy (#52)")
struct StoreScratchCopyTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("scratch-copy-\(UUID().uuidString)", isDirectory: true)

    private var store: URL { root.appendingPathComponent("source/LittleOrbit.store") }
    private var wal: URL { URL(fileURLWithPath: store.path + "-wal") }
    private var shm: URL { URL(fileURLWithPath: store.path + "-shm") }
    private var scratch: URL { root.appendingPathComponent("scratch", isDirectory: true) }

    private func prepare(withCompanions: Bool = true) throws {
        try FileManager.default.createDirectory(
            at: store.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("main".utf8).write(to: store)
        if withCompanions {
            try Data("wal".utf8).write(to: wal)
            try Data("shm".utf8).write(to: shm)
        }
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    @Test("The store, -wal and -shm are copied byte for byte")
    func copiesAllFiles() throws {
        defer { cleanUp() }
        try prepare()
        let copy = try StoreScratchCopy.copy(store, into: scratch)
        #expect(try Data(contentsOf: copy) == Data("main".utf8))
        #expect(try Data(contentsOf: URL(fileURLWithPath: copy.path + "-wal")) == Data("wal".utf8))
        #expect(try Data(contentsOf: URL(fileURLWithPath: copy.path + "-shm")) == Data("shm".utf8))
    }

    @Test("A store without companions is copied alone")
    func copiesWithoutCompanions() throws {
        defer { cleanUp() }
        try prepare(withCompanions: false)
        let copy = try StoreScratchCopy.copy(store, into: scratch)
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path) == ["LittleOrbit.store"])
        #expect(try Data(contentsOf: copy) == Data("main".utf8))
    }

    @Test("The store changing once during the copy is retried, and the retry copies the new state")
    func storeChangeIsRetriedOnce() throws {
        defer { cleanUp() }
        try prepare()
        var calls = 0
        let copy = try StoreScratchCopy.copy(store, into: scratch) {
            calls += 1
            if calls == 1 {
                try? append("-checkpointed", to: store)
            }
        }
        #expect(calls == 2)
        #expect(try Data(contentsOf: copy) == Data("main-checkpointed".utf8))
    }

    @Test("The -wal changing once during the copy is retried")
    func walChangeIsRetriedOnce() throws {
        defer { cleanUp() }
        try prepare()
        var calls = 0
        let copy = try StoreScratchCopy.copy(store, into: scratch) {
            calls += 1
            if calls == 1 {
                try? append("-restarted", to: wal)
            }
        }
        #expect(calls == 2)
        #expect(try Data(contentsOf: URL(fileURLWithPath: copy.path + "-wal")) == Data("wal-restarted".utf8))
    }

    @Test("A store that changes during both attempts throws changedDuringCopy, which counts as holding data")
    func repeatedChangeThrows() throws {
        defer { cleanUp() }
        try prepare()
        var calls = 0
        #expect(throws: StoreScratchCopy.Failure.changedDuringCopy) {
            try StoreScratchCopy.copy(store, into: scratch) {
                calls += 1
                try? append("+", to: store)
            }
        }
        #expect(calls == 2)
    }

    @Test("A -wal that appears during the copy is a change, so the copy is retried and includes it")
    func walAppearingIsAChange() throws {
        defer { cleanUp() }
        try prepare(withCompanions: false)
        var calls = 0
        let copy = try StoreScratchCopy.copy(store, into: scratch) {
            calls += 1
            if calls == 1 {
                try? Data("new wal".utf8).write(to: wal)
            }
        }
        #expect(calls == 2)
        #expect(try Data(contentsOf: URL(fileURLWithPath: copy.path + "-wal")) == Data("new wal".utf8))
    }

    @Test("A store that can't be copied throws copyFailed")
    func missingStoreFailsToCopy() {
        defer { cleanUp() }
        #expect(throws: StoreScratchCopy.Failure.copyFailed) {
            try StoreScratchCopy.copy(store, into: scratch)
        }
    }

    @Test("Leftover scratch folders older than the limit are removed; fresh ones and other folders stay")
    func removesOldLeftovers() throws {
        defer { cleanUp() }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let old = StoreScratchCopy.newScratchFolder(in: root)
        let fresh = StoreScratchCopy.newScratchFolder(in: root)
        let other = root.appendingPathComponent("not-a-probe", isDirectory: true)
        for folder in [old, fresh, other] {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("ledger copy".utf8).write(to: folder.appendingPathComponent("LittleOrbit.store"))
        }
        let longAgo = Date().addingTimeInterval(-(StoreScratchCopy.leftoverAge + 60))
        try fileManager.setAttributes([.modificationDate: longAgo], ofItemAtPath: old.path)
        try fileManager.setAttributes([.modificationDate: longAgo], ofItemAtPath: other.path)
        StoreScratchCopy.removeLeftovers(in: root)
        #expect(!fileManager.fileExists(atPath: old.path))
        #expect(fileManager.fileExists(atPath: fresh.path), "A probe that is still running keeps its folder")
        #expect(fileManager.fileExists(atPath: other.path))
    }

    @Test("Scratch folders carry the app-specific prefix")
    func scratchFoldersNameTheApp() {
        let folder = StoreScratchCopy.newScratchFolder(in: root)
        #expect(StoreScratchCopy.folderPrefix == "littleorbit-store-probe-")
        #expect(folder.lastPathComponent.hasPrefix("littleorbit-store-probe-"))
    }

    @Test("The sweep leaves other apps' similarly named folders alone, however old")
    func sweepLeavesOtherAppsAlone() throws {
        defer { cleanUp() }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let names = [
            "store-probe-x",
            "com.example.other-store-probe-1",
            "otherapp-littleorbit-store-probe-1",
            "littleorbit-store-probe",
            "LittleOrbit-Store-Probe-1",
        ]
        let others = names.map { root.appendingPathComponent($0, isDirectory: true) }
        let longAgo = Date().addingTimeInterval(-(StoreScratchCopy.leftoverAge + 60))
        for folder in others {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try fileManager.setAttributes([.modificationDate: longAgo], ofItemAtPath: folder.path)
        }
        StoreScratchCopy.removeLeftovers(in: root)
        for folder in others {
            #expect(fileManager.fileExists(atPath: folder.path), "\(folder.lastPathComponent) isn't ours")
        }
    }
}
