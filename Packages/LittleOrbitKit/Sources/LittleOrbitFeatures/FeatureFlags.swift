/// Build switches for features that ship only once their work lands.
public enum FeatureFlags {
    /// Budgets (#25). Off in 1.0 unless the #25 stack lands before the release cut (D423). While it's off, the Mac
    /// sidebar and the iPhone and iPad Accounts home have no Budgets row, so no path leads to the placeholder
    /// (D422.1). It only hides those entry points: budget data stays in the store, and backups export and restore
    /// it unchanged (D423.3). The #25 stack turns Budgets on by setting this to `true`.
    public static let budgetsEnabled = false
}
