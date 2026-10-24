import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

/// D291.1: the merge refusal's message names the first clashing subcategory in a locale-aware sort.
@Suite("Category merge clash (D291.1)")
struct CategoryMergeClashPresentationTests {
    private func clash(_ names: [String]) -> CategoryMergeClash {
        CategoryMergeClash(
            sourceID: UUID(),
            sourceName: "Leisure",
            survivorID: UUID(),
            survivorName: "Entertainment",
            clashingNames: names,
        )
    }

    @Test("The first clash is the first name in localizedStandardCompare order, whatever the stored order")
    func firstClash() {
        #expect(clash(["Movies"]).firstClashingName == "Movies")
        #expect(clash(["Movies", "games", "Books"]).firstClashingName == "Books")
        #expect(clash(["Movies 10", "Movies 2"]).firstClashingName == "Movies 2")
        #expect(clash(["Movies", "games", "Books"]).count == 3)
    }
}
