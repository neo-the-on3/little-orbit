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
}
