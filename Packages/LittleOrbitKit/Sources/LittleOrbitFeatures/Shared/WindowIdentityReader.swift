#if canImport(SwiftUI) && (os(iOS) || os(macOS))
    import SwiftUI

    #if os(iOS)
        import UIKit
    #else
        import AppKit
    #endif

    /// Reports the identifier of the window it's in, so a tapped reminder opens in the right one (S33, Tech
    /// Architect NB2): on iOS the scene session's persistent identifier, which a notification response names as its
    /// target scene, and on the Mac the window number. It reports `nil` once it leaves its window.
    struct WindowIdentityReader {
        let onChange: (String?) -> Void
    }

    #if os(iOS)
        extension WindowIdentityReader: UIViewRepresentable {
            func makeUIView(context: Context) -> ReportingView {
                let view = ReportingView()
                view.onChange = onChange
                return view
            }

            func updateUIView(_ view: ReportingView, context: Context) {
                view.onChange = onChange
            }

            final class ReportingView: UIView {
                var onChange: ((String?) -> Void)?

                override func didMoveToWindow() {
                    super.didMoveToWindow()
                    onChange?(window?.windowScene?.session.persistentIdentifier)
                }
            }
        }
    #else
        extension WindowIdentityReader: NSViewRepresentable {
            func makeNSView(context: Context) -> ReportingView {
                let view = ReportingView()
                view.onChange = onChange
                return view
            }

            func updateNSView(_ view: ReportingView, context: Context) {
                view.onChange = onChange
            }

            final class ReportingView: NSView {
                var onChange: ((String?) -> Void)?

                override func viewDidMoveToWindow() {
                    super.viewDidMoveToWindow()
                    onChange?(window.map { String($0.windowNumber) })
                }
            }
        }
    #endif

    extension View {
        /// Keeps `id` set to this main window's identifier, and `taps` told which main windows are up.
        func reportsReminderWindow(to taps: ScheduledReminderTaps?, id: Binding<String?>) -> some View {
            background(
                WindowIdentityReader { new in
                    if let old = id.wrappedValue, old != new {
                        taps?.windowClosed(old)
                    }
                    id.wrappedValue = new
                    if let new {
                        taps?.windowAppeared(new)
                    }
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            )
            .onDisappear {
                if let old = id.wrappedValue {
                    taps?.windowClosed(old)
                }
            }
        }
    }
#endif
