#if canImport(SwiftData)
    import Foundation
    import LittleOrbitDomain
    import Testing

    @testable import LittleOrbitPersistence

    /// #52: the store home is recorded when SwiftData opens the store, and "holds data" means accounts or
    /// transactions.
    @MainActor
    @Suite("Store home with SwiftData (#52)")
    struct StoreHomeSwiftDataTests {
        private static let group = "group.test.store"
        private static let bundle = "test.store.app"

        private let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-home-swiftdata-\(UUID().uuidString)", isDirectory: true)

        private var support: URL { root.appendingPathComponent("support", isDirectory: true) }
        private var container: URL { root.appendingPathComponent("group", isDirectory: true) }
        private var marker: FileStoreHomeMarkerStore {
            .appFolder(applicationSupport: support, bundleIdentifier: Self.bundle)
        }

        private func appLocal() throws -> StoreConfiguration {
            let container = container
            let group = Self.group
            return try StoreConfiguration.appLocal(
                applicationSupport: support,
                bundleIdentifier: Self.bundle,
                appGroupIdentifier: group,
                groupContainer: AppGroupContainerLookup { $0 == group ? container : nil },
                entitlement: .granted,
            )
        }

        private func cleanUp() {
            try? FileManager.default.removeItem(at: root)
        }

        @Test("Opening the app's store records marker=group with the store's ID, before any write")
        func makeContainerRecordsTheHome() throws {
            defer { cleanUp() }
            let configuration = try appLocal()
            _ = try LittleOrbitStore.makeRepository(configuration: configuration)
            let fileURL = try #require(configuration.fileURL)
            guard case .recorded(let home) = marker.read() else {
                Issue.record("No marker after the store opened")
                return
            }
            #expect(home.isSameLocation(as: .group(Self.group)))
            #expect(home.storeID != nil)
            #expect(home.storeID == StoreIdentity.read(forStoreAt: fileURL))
            #expect(FileStoreHomeMarkerStore.groupCopy(container: container).read() == .recorded(home))
        }

        @Test("A read-only open records nothing")
        func readOnlyRecordsNothing() throws {
            defer { cleanUp() }
            let configuration = try appLocal()
            _ = try LittleOrbitStore.makeRepository(configuration: StoreConfiguration(fileURL: configuration.fileURL))
            var readOnly = configuration
            readOnly.readOnly = true
            _ = try LittleOrbitStore.makeRepository(configuration: readOnly)
            #expect(marker.read() == .missing)
        }

        @Test("A store holds data once it has an account; seeded categories alone don't count")
        func probeCountsAccountsAndTransactions() throws {
            defer { cleanUp() }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("LittleOrbit.store")
            #expect(!StoreContentsProbe.hasRecords(at: url))
            let repository = try LittleOrbitStore.makeRepository(configuration: StoreConfiguration(fileURL: url))
            try repository.seedDefaultCategories()
            #expect(!StoreContentsProbe.hasRecords(at: url))
            try repository.saveAccount(Account(name: "Cash", currencyCode: "INR", openingBalance: 0))
            #expect(StoreContentsProbe.hasRecords(at: url))
        }

        // MARK: - The probe is read-only (B2)

        /// Writes a store and releases its container before returning, so the store is cleanly closed.
        private func writeClosedStore(at url: URL, withAccount: Bool) throws {
            let repository = try LittleOrbitStore.makeRepository(configuration: StoreConfiguration(fileURL: url))
            try repository.seedDefaultCategories()
            if withAccount {
                try repository.saveAccount(Account(name: "Cash", currencyCode: "INR", openingBalance: 0))
            }
        }

        /// Every file and folder under `folder`, by relative path, with each file's bytes. Equal snapshots mean the
        /// same names, sizes and contents, including any `-wal`, `-shm` or `.id` file.
        private func snapshot(_ folder: URL) throws -> [String: Data] {
            var result: [String: Data] = [:]
            let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
            let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys)
            let prefix = folder.standardizedFileURL.path + "/"
            while let item = enumerator?.nextObject() as? URL {
                let path = String(item.standardizedFileURL.path.dropFirst(prefix.count))
                let values = try item.resourceValues(forKeys: Set(keys))
                if values.isDirectory == true {
                    result[path + "/"] = Data()
                } else if values.isRegularFile == true {
                    result[path] = try Data(contentsOf: item)
                }
            }
            return result
        }

        @Test("A cleanly closed store with only seeded categories reports no data")
        func closedSeededStoreIsEmpty() throws {
            defer { cleanUp() }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("LittleOrbit.store")
            try writeClosedStore(at: url, withAccount: false)
            #expect(!StoreContentsProbe.hasRecords(at: url))
        }

        @Test("A cleanly closed store with an account reports data")
        func closedStoreWithAccountHasData() throws {
            defer { cleanUp() }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("LittleOrbit.store")
            try writeClosedStore(at: url, withAccount: true)
            #expect(StoreContentsProbe.hasRecords(at: url))
        }

        @Test("Probing a closed store leaves its bytes and its folder listing unchanged")
        func probeLeavesClosedStoreUnchanged() throws {
            defer { cleanUp() }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("LittleOrbit.store")
            try writeClosedStore(at: url, withAccount: true)
            let before = try snapshot(root)
            #expect(before["LittleOrbit.store"] != nil)
            #expect(StoreContentsProbe.hasRecords(at: url))
            #expect(!StoreContentsProbe.hasRecords(at: root.appendingPathComponent("Missing.store")))
            #expect(try snapshot(root) == before)
        }

        @Test("Probing a store the app has open leaves its bytes, -wal and -shm unchanged")
        func probeLeavesOpenStoreUnchanged() throws {
            defer { cleanUp() }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("LittleOrbit.store")
            let repository = try LittleOrbitStore.makeRepository(configuration: StoreConfiguration(fileURL: url))
            try repository.saveAccount(Account(name: "Cash", currencyCode: "INR", openingBalance: 0))
            let before = try snapshot(root)
            #expect(StoreContentsProbe.hasRecords(at: url), "A write still in the WAL is counted")
            #expect(try snapshot(root) == before)
            #expect(try repository.accounts().map(\.name) == ["Cash"])
        }

        @Test("A store that changes during every copy attempt counts as holding data (changedDuringCopy)")
        func tornCopyCountsAsData() throws {
            defer { cleanUp() }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("LittleOrbit.store")
            try writeClosedStore(at: url, withAccount: false)
            let wal = URL(fileURLWithPath: url.path + "-wal")
            // Every attempt sees the -wal grow, as a second writer would make it.
            let result = StoreContentsProbe.probe(url) {
                let grown = ((try? Data(contentsOf: wal)) ?? Data()) + Data("+".utf8)
                try? grown.write(to: wal)
            }
            #expect(result == .failed(.changedDuringCopy))
            #expect(result.countsAsData, "Never a false empty")
        }

        @Test("A store that changes once during the copy is copied again and counted")
        func changeOnceIsRetried() throws {
            defer { cleanUp() }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("LittleOrbit.store")
            let other = root.appendingPathComponent("Other.store")
            try writeClosedStore(at: url, withAccount: false)
            try writeClosedStore(at: other, withAccount: true)
            var calls = 0
            // The first attempt sees the store replaced by one that holds data; the retry copies that state.
            let result = StoreContentsProbe.probe(url) {
                calls += 1
                if calls == 1 {
                    for suffix in ["", "-wal", "-shm"] {
                        let target = URL(fileURLWithPath: url.path + suffix)
                        let source = URL(fileURLWithPath: other.path + suffix)
                        try? FileManager.default.removeItem(at: target)
                        if FileManager.default.fileExists(atPath: source.path) {
                            try? FileManager.default.copyItem(at: source, to: target)
                        }
                    }
                }
            }
            #expect(calls == 2)
            #expect(result == .hasData)
        }

        @Test("A file that isn't a store counts as holding data, and is left unchanged")
        func garbageFileHasData() throws {
            defer { cleanUp() }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("LittleOrbit.store")
            try Data("this is not a SQLite store".utf8).write(to: url)
            let before = try snapshot(root)
            #expect(StoreContentsProbe.probe(url) == .failed(.openFailed))
            #expect(try snapshot(root) == before)
        }
    }
#endif
