import Testing

@testable import LittleOrbitFeatures

/// The stale-step alert's count message (D189.2, #103 X5): one message for changed, deleted or both, with
/// the catalog's plural forms.
@Suite("Stale-step alert text")
struct StaleTextTests {
    @Test("Two or more stale records are counted in one message, changed or deleted")
    func counted() {
        #expect(
            StaleText.changedOrDeleted(2)
                == "2 of these transactions have changed or been deleted since then. Nothing was changed."
        )
        #expect(
            StaleText.changedOrDeleted(5)
                == "5 of these transactions have changed or been deleted since then. Nothing was changed."
        )
    }

    #if canImport(Darwin)
        @Test("The String Catalog's singular form is used for a count of one")
        func singular() {
            #expect(
                StaleText.changedOrDeleted(1)
                    == "1 of these transactions has changed or been deleted since then. Nothing was changed."
            )
        }
    #endif
}
