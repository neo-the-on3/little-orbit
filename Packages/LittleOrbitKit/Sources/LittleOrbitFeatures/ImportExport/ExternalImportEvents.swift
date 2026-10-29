import Foundation
import Observation

/// Files opened from outside the app, waiting for one main window to take them (#189, Tech Architect on #339). The
/// open handlers sit on every main window, so each window the system hands an event to posts it here, and exactly
/// one window takes it: the main window last made key (the frontmost), else the window that was handed it, else
/// the first main window up, as when a Dock or Finder open starts the app. Only the latest event waits. Windows
/// take it as the waiting event changes, so every post from one event lands before any window takes it.
@MainActor
@Observable
public final class ExternalImportEvents {
    /// One open event.
    public struct Event: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let urls: [URL]
        /// The window the system handed it to.
        let poster: UUID
    }

    public private(set) var pending: Event?
    /// The main windows that are up, oldest first.
    private var windows: [UUID] = []
    /// The main window last made key.
    private var lastKey: UUID?

    public init() {}

    /// `window` was handed `urls`. Returns `false` when they're the files of the event still waiting, which another
    /// window was handed too; otherwise this event replaces any still waiting.
    @discardableResult
    public func post(_ urls: [URL], from window: UUID) -> Bool {
        guard pending?.urls != urls else {
            return false
        }
        pending = Event(id: UUID(), urls: urls, poster: window)
        return true
    }

    /// The window that takes the waiting event, or `nil` while no main window is up.
    public var receiver: UUID? {
        if let lastKey, windows.contains(lastKey) {
            return lastKey
        }
        if let poster = pending?.poster, windows.contains(poster) {
            return poster
        }
        return windows.first
    }

    /// The waiting event's files, once, if `window` is the one that takes it.
    public func take(for window: UUID) -> [URL]? {
        guard let pending, receiver == window else {
            return nil
        }
        self.pending = nil
        return pending.urls
    }

    public func windowAppeared(_ window: UUID) {
        if !windows.contains(window) {
            windows.append(window)
        }
    }

    public func windowBecameKey(_ window: UUID) {
        lastKey = window
    }

    public func windowClosed(_ window: UUID) {
        windows.removeAll { $0 == window }
        if lastKey == window {
            lastKey = nil
        }
    }
}
