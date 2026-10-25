#if canImport(SwiftUI) && os(macOS) && DEBUG
    import SwiftUI

    /// Debug builds only: applies `-LittleOrbitScheduledColumns` (`ScheduledColumnsLaunchPreset`) to the
    /// "scheduledTableColumns" scene storage before `content`, the Table, is first built and reads it. With no
    /// preset for this window it shows `content` straight away.
    ///
    /// `garbage` and `reset` write the key's raw value through a `Data` scene storage under the same key: that's
    /// the value the Table's `TableColumnCustomization` storage reads back, so undecodable bytes prove its fallback
    /// to the defaults (Repeat hidden), and nil removes the saved choice.
    struct ScheduledColumnsLaunchGate<Content: View>: View {
        @SceneStorage(ScheduledTableView.columnsKey) private var raw: Data?
        @State private var preset = ScheduledColumnsLaunchPreset.take()
        @State private var isApplied = false
        @ViewBuilder let content: Content

        var body: some View {
            if preset == nil || isApplied {
                content
            } else {
                Color.clear
                    .task {
                        switch preset {
                        case .garbage: raw = ScheduledColumnsLaunchPreset.garbageValue
                        case .reset, .repeatShown: raw = nil
                        case nil: break
                        }
                        isApplied = true
                    }
            }
        }
    }
#endif
