#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import Foundation
    import LittleOrbitDomain
    import SwiftUI

    extension View {
        /// Gives a window its own undo history (D187.2): the history registers its steps on this window's
        /// `UndoManager`, the window's views find it in the environment, and the off-screen notice (D164.3)
        /// shows under the toolbar on macOS and at the bottom on iOS. `onShow` goes to an account; only Show
        /// calls it.
        func undoWindow(_ history: WindowUndoHistory, onShow: @escaping (UUID) -> Void) -> some View {
            modifier(UndoWindowModifier(history: history, onShow: onShow))
        }
    }

    private struct UndoWindowModifier: ViewModifier {
        let history: WindowUndoHistory
        let onShow: (UUID) -> Void
        @Environment(\.undoManager) private var undoManager
        @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

        /// Under the toolbar on macOS; above the bottom safe area on iOS and iPadOS (D164.3).
        #if os(macOS)
            private static let noticeEdge = VerticalEdge.top
        #else
            private static let noticeEdge = VerticalEdge.bottom
        #endif

        func body(content: Content) -> some View {
            content
                .environment(history)
                .safeAreaInset(edge: Self.noticeEdge, spacing: 0) {
                    if let notice = history.notice {
                        UndoNoticeView(
                            notice: notice,
                            onShow: { accountID in
                                history.dismissNotice()
                                onShow(accountID)
                            },
                            onDismiss: { history.dismissNotice() },
                        )
                        .transition(.move(edge: Self.noticeEdge == .top ? .top : .bottom).combined(with: .opacity))
                    }
                }
                .animation(.default, value: history.notice)
                // This window's own UndoManager holds its steps.
                .onChange(of: undoManager.map(ObjectIdentifier.init), initial: true) {
                    history.announce = { AccessibilityNotification.Announcement($0).post() }
                    // The history follows the UndoManager's own notifications from here (B1).
                    history.attach(undoManager)
                }
                .task(id: history.notice?.id) {
                    guard let notice = history.notice else {
                        return
                    }
                    AccessibilityNotification.Announcement(notice.message).post()
                    // About 8 seconds, like the toast; with VoiceOver it stays until dismissed or the next action,
                    // so Show can be reached (D165.3).
                    guard !voiceOverEnabled else {
                        return
                    }
                    try? await Task.sleep(for: .seconds(8))
                    if !Task.isCancelled, history.notice?.id == notice.id {
                        history.dismissNotice()
                    }
                }
                // A stale step says why and is gone; a failure keeps the step (D187.5, X1–X10). OK is the
                // only button.
                .alert(
                    history.alert?.title ?? "",
                    isPresented: Binding(get: { history.alert != nil }, set: { if !$0 { history.dismissAlert() } }),
                    presenting: history.alert,
                ) { _ in
                    Button("OK") { history.dismissAlert() }
                } message: { alert in
                    Text(alert.message)
                }
        }
    }
#endif
