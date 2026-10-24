import Foundation
import LittleOrbitDomain

extension CategoryMergeClash {
    /// The clashing name the “Can’t Merge Categories” message names (%4$@, D291.1): the first in a locale-aware
    /// sort (`localizedStandardCompare`), so “Movies 2” comes before “Movies 10”.
    public var firstClashingName: String {
        clashingNames.min { $0.localizedStandardCompare($1) == .orderedAscending } ?? ""
    }
}
