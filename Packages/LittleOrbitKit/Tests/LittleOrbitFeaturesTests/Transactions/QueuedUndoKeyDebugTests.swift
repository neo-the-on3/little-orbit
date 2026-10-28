import Foundation
import Testing

@testable import LittleOrbitFeatures

/// Debug › Send Queued ⌘Z (n2 on #201): when it sends its ⌘Z, and with what press time. The key-down itself and
/// `NSApp.postEvent(_:atStart:)` are AppKit's, checked by Tester2 in a Debug Mac build; the drop it then gets is
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

    @Test("Send ⇧⌘Z Right After Batch: ⇧⌘Z as AppKit reports a typed one, signposted redoAtSend")
    func redoKeyAndTags() {
        #expect(QueuedUndoKeyDebug.key(for: .undo) == .init(characters: "z", shift: false))
        #expect(QueuedUndoKeyDebug.key(for: .redo) == .init(characters: "Z", shift: true))
        let redo = QueuedUndoKeyDebug.key(for: .redo)
        #expect(
            UndoKeyPolicy.command(characters: redo.characters, modifiers: [.command, .shift]) == .redo,
            "The monitor reads it as Redo",
        )
        #expect(QueuedUndoKeyDebug.tag(.whenChosen, .undo).description == "whenChosen")
        #expect(QueuedUndoKeyDebug.tag(.atSend, .undo).description == "atSend")
        #expect(QueuedUndoKeyDebug.tag(.atSend, .redo).description == "redoAtSend")
        #expect(QueuedUndoKeyDebug.tag(.whenChosen, .redo).description == "redoWhenChosen")
    }

    /// The AppKit send can't run here, so this reads the source: Tester2 at 7c8a893 never saw the monitor act,
    /// because `NSApp.sendEvent(_:)` skips local monitors, which run as an event is dequeued.
    @Test("The Debug key-down is posted to the event queue, never handed to sendEvent, so the monitor sees it")
    func postsToTheQueue() throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appending(path: "Sources/LittleOrbitFeatures/Transactions/QueuedUndoKeyDebug.swift"),
            encoding: .utf8,
        )
        let code = source.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        #expect(code.contains { $0.contains("NSApp.postEvent(event, atStart: false)") })
        #expect(!code.contains { $0.contains("NSApp.sendEvent(") })
        let app = try String(
            contentsOf: root.appending(path: "../../Apps/Shared/ScheduledReminderTapDebug.swift"),
            encoding: .utf8,
        )
        #expect(app.contains("Text(verbatim: \"Send ⇧⌘Z Right After Batch\")"))
        #expect(app.contains("redo: true"))
    }

    /// Tester2 at 1aa17a3 (6473659858): chosen 527 ms into a batch, the key window was its progress sheet, gone
    /// by the send, so (1), (3) and (7) logged `notKeyWindow`. The window is read as the key-down is posted.
    @Test(
        "The key-down goes to the key window at the send, not the one when chosen",
        arguments: [QueuedUndoKeyDebug.Stamp.whenChosen, .atSend],
    )
    func keyWindowReadAtSend(stamp: QueuedUndoKeyDebug.Stamp) async throws {
        let updates = LedgerUpdates()
        var now: TimeInterval = 40
        updates.uptime = { now }
        #expect(updates.beginBatch())
        // The progress sheet is key as the command is chosen, and gone with the batch.
        var keyWindow: Int? = 7
        var posted: [Int] = []
        var checks = 0
        let task = QueuedUndoKeyDebug.pressForKeyWindow(
            updates: updates,
            stamp: stamp,
            command: stamp == .atSend ? .redo : .undo,
            uptime: { now },
            sleep: { _ in
                checks += 1
                if checks == 2 {
                    now = 41
                    updates.endBatch()
                    keyWindow = 3
                }
            },
            keyWindowNumber: { keyWindow },
            post: { _, number in posted.append(number) },
        )
        await task.value
        #expect(posted == [3], "The main window, key at the send; never the sheet's 7")
    }

    @Test("No key window at the send: nothing is posted, never to the main window or a stale one")
    func noKeyWindowPostsNothing() async {
        let updates = LedgerUpdates()
        var asked = 0
        var posted: [Int] = []
        let task = QueuedUndoKeyDebug.pressForKeyWindow(
            updates: updates,
            stamp: .atSend,
            uptime: { 5 },
            sleep: { _ in },
            keyWindowNumber: {
                asked += 1
                return nil
            },
            post: { _, number in posted.append(number) },
        )
        await task.value
        #expect(posted.isEmpty)
        #expect(asked == 1, "Read once, at the send")
    }
}
