import Foundation
import Testing

@testable import LittleOrbitFeatures

/// Debug › Send Queued ⌘Z (n2 on #201): when it sends its ⌘Z, and with what press time. The key-down itself and
/// `NSApp.sendEvent(_:)` are AppKit's, checked by Tester2 in a Debug Mac build; the drop it then gets is
/// `QueuedDispatchTests`'. Mutants: sending as soon as it's chosen fails `inBatchWaits`; taking the press time at
/// the send fails `inBatchKeepsPressTime`; dropping the `#if DEBUG` fails `debugOnly`. For Send ⌘Z Right After
/// Batch (`.atSend`): keeping the chosen time fails `atSendStampsAfterEnd`; sending before the end fails it too.
@MainActor
@Suite("Debug › Send Queued ⌘Z", .timeLimit(.minutes(1)))
struct QueuedUndoKeyDebugTests {
    @Test("Chosen during a batch: sent only after the batch ends, on a later check")
    func inBatchWaits() async throws {
        let updates = LedgerUpdates()
        var now: TimeInterval = 10
        updates.uptime = { now }
        #expect(updates.beginBatch())
        var sent: [TimeInterval] = []
        var checks = 0
        let task = QueuedUndoKeyDebug.press(
            updates: updates,
            uptime: { now },
            sleep: { _ in
                checks += 1
                if checks == 3 {
                    now = 11
                    updates.endBatch()
                }
                await Task.yield()
            },
            send: { sent.append($0) },
        )
        await task.value
        #expect(updates.lastBatch == 10...11)
        #expect(sent == [10], "Once, after the end, stamped inside the batch")
        #expect(checks == 3)
    }

    @Test("The press time is the one when it was chosen, inside the batch, not the send's")
    func inBatchKeepsPressTime() async throws {
        let updates = LedgerUpdates()
        var now: TimeInterval = 20
        updates.uptime = { now }
        #expect(updates.beginBatch())
        now = 20.4
        var sent: [TimeInterval] = []
        let task = QueuedUndoKeyDebug.press(
            updates: updates,
            uptime: { now },
            sleep: { _ in
                now += 0.3
                if updates.isBatchRunning {
                    updates.endBatch()
                }
            },
            send: { sent.append($0) },
        )
        await task.value
        #expect(sent == [20.4])
        let batch = try #require(updates.lastBatch)
        #expect(batch.contains(20.4), "So the policy drops it")
        let drops = QueuedCommandPolicy.dropsCommand(eventTime: 20.4, lastBatch: batch, lastDroppedEventTime: nil)
        #expect(drops)
    }

    @Test("The control: chosen outside a batch, sent once on the next check, stamped now, which no batch holds")
    func outsideBatchSendsOnce() async throws {
        let updates = LedgerUpdates()
        var checks = 0
        var sent: [TimeInterval] = []
        let task = QueuedUndoKeyDebug.press(
            updates: updates,
            uptime: { 5 },
            sleep: { _ in checks += 1 },
            send: { sent.append($0) },
        )
        await task.value
        #expect(sent == [5])
        #expect(checks == 1)
        let drops = QueuedCommandPolicy.dropsCommand(
            eventTime: 5,
            lastBatch: updates.lastBatch,
            lastDroppedEventTime: nil,
        )
        #expect(!drops, "So Undo runs")
    }

    @Test("Right after the batch (.atSend): sent once after the end, stamped then, outside the batch, so Undo runs")
    func atSendStampsAfterEnd() async throws {
        let updates = LedgerUpdates()
        var now: TimeInterval = 30
        updates.uptime = { now }
        #expect(updates.beginBatch())
        now = 30.2
        var sent: [TimeInterval] = []
        var checks = 0
        let task = QueuedUndoKeyDebug.press(
            updates: updates,
            stamp: .atSend,
            uptime: { now },
            sleep: { _ in
                checks += 1
                if checks == 2 {
                    now = 31
                    updates.endBatch()
                }
                now += 0.02
            },
            send: { sent.append($0) },
        )
        await task.value
        let batch = try #require(updates.lastBatch)
        #expect(batch == 30...31)
        #expect(sent.count == 1)
        let stamped = try #require(sent.first)
        #expect(stamped > batch.upperBound, "Stamped after the end, not when chosen")
        let drops = QueuedCommandPolicy.dropsCommand(eventTime: stamped, lastBatch: batch, lastDroppedEventTime: nil)
        #expect(!drops, "So Undo runs once")
    }

    /// The release check a test can see: tests build Debug only, so it reads the source and checks the whole file
    /// is inside `#if DEBUG`, and that the app's menu item is too.
    @Test("Compiled out of release: the file and the app's menu item are inside #if DEBUG")
    func debugOnly() throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appending(path: "Sources/LittleOrbitFeatures/Transactions/QueuedUndoKeyDebug.swift"),
            encoding: .utf8,
        )
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.first == "#if DEBUG")
        let last = lines.last(where: { !$0.isEmpty })
        #expect(last == "#endif")
        let directives = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        let opens = directives.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#if") }.count
        let closes = directives.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#endif") }.count
        #expect(opens == closes)
        #expect(!directives.contains { $0.contains("#else") }, "No release branch")
        let app = try String(
            contentsOf: root.appending(path: "../../Apps/Shared/ScheduledReminderTapDebug.swift"),
            encoding: .utf8,
        )
        #expect(app.hasPrefix("// ") && app.contains("#if (os(iOS) || os(macOS)) && DEBUG\n"))
        let guardLine = try #require(app.range(of: "#if (os(iOS) || os(macOS)) && DEBUG\n"))
        let use = try #require(app.range(of: "QueuedUndoKeyDebug.sendQueuedUndo"))
        #expect(guardLine.upperBound < use.lowerBound)
        let tail = app[guardLine.upperBound...]
        #expect(tail.components(separatedBy: "#if ").count == tail.components(separatedBy: "#endif").count - 1)
    }
}
