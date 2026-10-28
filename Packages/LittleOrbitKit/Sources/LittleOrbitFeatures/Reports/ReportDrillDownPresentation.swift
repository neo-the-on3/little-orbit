/// Which report row's drill-down is pushed (#315). A click calls `open(_:)` every time, and Back sets
/// `isPresented` to false, which forgets the row. So the next click on the same row pushes it again.
///
/// A Mac `List` row that's a `NavigationLink` stays selected after Back, and clicking a selected row isn't a
/// change, so it didn't push again (#315). The Mac report opens rows through this instead. iOS keeps its
/// links: a tapped row there isn't left selected.
public struct ReportDrillDownPresentation<Row: Equatable>: Equatable {
    /// The row whose drill-down is pushed, or `nil` when the report itself is on screen.
    public private(set) var row: Row?

    public init() {}

    /// Pushes `row`'s drill-down, even when it's the row that was open last.
    public mutating func open(_ row: Row) {
        self.row = row
    }

    /// The `navigationDestination(isPresented:)` binding: true while a row is pushed. Back sets it to false.
    public var isPresented: Bool {
        get { row != nil }
        set {
            if !newValue {
                row = nil
            }
        }
    }
}
