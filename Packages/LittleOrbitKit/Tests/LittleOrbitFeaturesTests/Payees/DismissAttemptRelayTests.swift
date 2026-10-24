import Foundation
import Testing

@testable import LittleOrbitFeatures

/// D300.1: a refused swipe down on an edit sheet asks “Discard Changes?”. The iOS bridge itself needs UIKit, so
/// these cover the parts it relies on: the current unsaved-edits state, and installing without wrapping a proxy.
@MainActor
@Suite("Swipe-down discard bridge")
struct DismissAttemptRelayTests {
    @Test("A swipe reads the unsaved-edits state as it is now, not when the bridge was set up")
    func readsCurrentState() {
        var requests: [Bool] = []
        let relay = DismissAttemptRelay(isDirty: false) { requests.append($0) }
        relay.isDirty = true
        relay.attempt()
        #expect(requests == [true])
        relay.isDirty = false
        relay.attempt()
        #expect(requests == [true, false])
    }

    @Test("A later update's request replaces the earlier one")
    func usesLatestRequest() {
        var first = 0
        var second = 0
        let relay = DismissAttemptRelay(isDirty: true) { _ in first += 1 }
        relay.request = { _ in second += 1 }
        relay.attempt()
        #expect(first == 0)
        #expect(second == 1)
    }

    @Test("Installing keeps our proxy, adopts another bridge's, and wraps anything else, never a proxy twice")
    func installSteps() {
        #expect(DismissAttemptInstall.step(delegateIsOurProxy: true, delegateIsProxy: true) == .keep)
        #expect(
            DismissAttemptInstall.step(delegateIsOurProxy: false, delegateIsProxy: true) == .adopt,
            "Another bridge's proxy is pointed at this relay, not wrapped",
        )
        #expect(
            DismissAttemptInstall.step(delegateIsOurProxy: false, delegateIsProxy: false) == .wrap,
            "SwiftUI set its own delegate again, so it's wrapped again",
        )
    }

    @Test("The prompt opens only when the state at the swipe has unsaved edits")
    func requestsDismissWithCurrentState() {
        var confirmation = DiscardConfirmation()
        let relay = DismissAttemptRelay(isDirty: false) { _ = confirmation.requestDismiss(isDirty: $0, from: .swipe) }
        relay.attempt()
        #expect(!confirmation.isPresented)
        relay.isDirty = true
        relay.attempt()
        #expect(confirmation.isPresentedFromSwipe)
    }

    /// A stand-in for a view controller: its parent, and whether it was itself presented.
    private final class Node {
        let parent: Node?
        let isPresented: Bool

        init(parent: Node? = nil, isPresented: Bool = false) {
            self.parent = parent
            self.isPresented = isPresented
        }
    }

    private func root(from node: Node?) -> Node? {
        DismissAttemptInstall.presentedRoot(from: node, parent: { $0.parent }, isPresented: { $0.isPresented })
    }

    @Test("The bridge installs on the sheet's presented root, found up its parents, never on itself")
    func findsPresentedRoot() {
        let sheet = Node(isPresented: true)
        let navigation = Node(parent: sheet)
        let bridge = Node(parent: navigation)
        #expect(root(from: bridge) === sheet)
        #expect(root(from: sheet) === sheet)
    }

    @Test("With no presented ancestor yet there's nothing to install on, so it tries again later")
    func noPresentedRoot() {
        let detached = Node()
        #expect(root(from: Node(parent: detached)) == nil)
        #expect(root(from: nil) == nil)
    }

    @Test("It stops at the nearest presented controller")
    func nearestPresented() {
        let outer = Node(isPresented: true)
        let inner = Node(parent: outer, isPresented: true)
        #expect(root(from: Node(parent: inner)) === inner)
    }

    // MARK: Refusing dismissal while edited (#167)

    @Test("A swipe down is refused while there are unsaved edits, read live, and the original isn't asked")
    func shouldDismissRefusesWhileDirty() {
        let relay = DismissAttemptRelay(isDirty: false)
        let sheet = FakeSheet(isModalInPresentation: false)
        DismissAttemptInstaller<FakeSheet>(relay: relay).install(on: sheet)
        var asked = 0
        let original = {
            asked += 1
            return true
        }
        #expect(relay.shouldDismiss(original: original))
        relay.isDirty = true
        #expect(!relay.shouldDismiss(original: original), "It follows the state after install")
        #expect(!relay.shouldDismiss(original: nil))
        #expect(asked == 1, "Only the clean answer asked the original")
        relay.isDirty = false
        #expect(relay.shouldDismiss(original: nil))
        #expect(sheet.modalWrites == 0)
    }

    @Test("With no unsaved edits the original delegate's answer passes through, and it's true when there's none")
    func shouldDismissWhenClean() {
        let relay = DismissAttemptRelay(isDirty: false)
        #expect(relay.shouldDismiss(original: { true }))
        #expect(!relay.shouldDismiss(original: { false }), "The original's refusal stands")
        #expect(relay.shouldDismiss(original: nil))
    }

    // MARK: Installing never touches whether the sheet is modal (#167)

    private final class FakeProxy {
        var relay: DismissAttemptRelay

        init(relay: DismissAttemptRelay) {
            self.relay = relay
        }
    }

    /// A presented sheet: its delegate, and whether it's modal, which only SwiftUI's interactiveDismissDisabled
    /// sets. It counts every change to `isModalInPresentation` the installer could make.
    private final class FakeSheet: DismissAttemptSheet {
        var delegate: AnyObject?
        var modalWrites = 0
        var isModalInPresentation: Bool {
            didSet { modalWrites += 1 }
        }

        init(isModalInPresentation: Bool) {
            self.isModalInPresentation = isModalInPresentation
        }

        var delegateProxy: FakeProxy? { delegate as? FakeProxy }

        func adopt(_ proxy: FakeProxy, relay: DismissAttemptRelay) {
            proxy.relay = relay
        }

        func wrapDelegate(relay: DismissAttemptRelay) -> FakeProxy {
            let proxy = FakeProxy(relay: relay)
            delegate = proxy
            return proxy
        }
    }

    @Test("Installing and re-installing never changes whether the sheet is modal, edited or not")
    func installLeavesModalAlone() {
        for isDirty in [true, false] {
            let sheet = FakeSheet(isModalInPresentation: isDirty)
            let relay = DismissAttemptRelay(isDirty: isDirty)
            let installer = DismissAttemptInstaller<FakeSheet>(relay: relay)
            #expect(installer.install(on: sheet) == .wrap)
            // The deferred re-install, and the appear and layout ones, with the state flipped in between.
            relay.isDirty.toggle()
            #expect(installer.install(on: sheet) == .keep)
            #expect(installer.install(on: sheet) == .keep)
            // SwiftUI sets its own delegate again, then the bridge installs again.
            sheet.delegate = NSObject()
            #expect(installer.install(on: sheet) == .wrap)
            #expect(sheet.isModalInPresentation == isDirty, "Only interactiveDismissDisabled sets it")
            #expect(sheet.modalWrites == 0)
        }
    }

    @Test("A re-install keeps one proxy, and adopts another bridge's proxy instead of wrapping it")
    func installerProxies() {
        let sheet = FakeSheet(isModalInPresentation: true)
        let relay = DismissAttemptRelay(isDirty: true)
        let installer = DismissAttemptInstaller<FakeSheet>(relay: relay)
        installer.install(on: sheet)
        let first = installer.proxy
        installer.install(on: sheet)
        #expect(installer.proxy === first)
        #expect(sheet.delegate === first)
        let other = DismissAttemptInstaller<FakeSheet>(relay: DismissAttemptRelay())
        #expect(other.install(on: sheet) == .adopt)
        #expect(sheet.delegate === first, "Not wrapped again")
        #expect(sheet.delegateProxy?.relay === other.relay)
        #expect(sheet.modalWrites == 0)
    }

    @Test("The iOS bridge's source never sets isModalInPresentation (#167)")
    func bridgeSourceHasNoModalWrite() throws {
        let shared = try #require(Self.sharedSourcesFolder(), "The Shared sources folder is found from this file")
        let files = try FileManager.default.contentsOfDirectory(atPath: shared.path).filter { $0.hasSuffix(".swift") }
        #expect(files.contains("DiscardConfirmationView.swift"), "The bridge's file is scanned")
        for name in files.sorted() {
            let source = try String(contentsOf: shared.appendingPathComponent(name), encoding: .utf8)
            let writes = Self.modalWrites(in: source)
            #expect(writes.isEmpty, "\(name): \(writes)")
        }
    }

    @Test("The source check finds every form of a write, and ignores comments and comparisons")
    func modalWriteScan() {
        #expect(Self.modalWrites(in: "root.isModalInPresentation = true").count == 1)
        #expect(Self.modalWrites(in: "  controller .isModalInPresentation=isDirty").count == 1)
        #expect(Self.modalWrites(in: "isModalInPresentation = false").count == 1)
        #expect(Self.modalWrites(in: "root.isModalInPresentation.toggle()").count == 1)
        #expect(Self.modalWrites(in: "x = 1 // root.isModalInPresentation = true").isEmpty)
        #expect(Self.modalWrites(in: "/// Never set `isModalInPresentation = isDirty` here.").isEmpty)
        #expect(Self.modalWrites(in: "if root.isModalInPresentation == isDirty {").isEmpty)
        #expect(Self.modalWrites(in: "if root.isModalInPresentation != isDirty {").isEmpty)
    }

    /// The package's Sources/LittleOrbitFeatures/Shared, found by walking up from this file to the folder with
    /// Package.swift, so moving the test within the package doesn't break it.
    private static func sharedSourcesFolder(from file: String = #filePath) -> URL? {
        var folder = URL(fileURLWithPath: file).deletingLastPathComponent()
        while folder.path != "/" {
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent("Package.swift").path) {
                return folder.appendingPathComponent("Sources/LittleOrbitFeatures/Shared")
            }
            folder = folder.deletingLastPathComponent()
        }
        return nil
    }

    /// The code lines that set `isModalInPresentation` (an assignment with any spacing, or `toggle()`), leaving
    /// out comment lines and trailing comments.
    private static func modalWrites(in source: String) -> [String] {
        source.split(separator: "\n")
            .compactMap { line in
                let code = String(
                    line.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                )
                guard !code.trimmingCharacters(in: .whitespaces).isEmpty,
                    code.contains(/isModalInPresentation\s*(=(?!=)|\.toggle\(\))/)
                else {
                    return nil
                }
                return String(line)
            }
    }
}
