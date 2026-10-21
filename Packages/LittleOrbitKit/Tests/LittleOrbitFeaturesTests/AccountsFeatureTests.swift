import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import Testing

@MainActor
@Suite("Accounts feature wiring")
struct AccountsFeatureTests {
    @Test("One list view model per feature, and a fresh form view model per sheet over the same use cases")
    func wiring() throws {
        let fake = FakeAccountUseCases()
        let feature = AccountsFeature(useCases: fake.useCases, defaultCurrency: "INR", locale: FeatureFixture.india)
        #expect(feature.accounts === feature.accounts)
        let first = feature.makeForm(.new)
        let second = feature.makeForm(.new)
        #expect(first !== second)
        #expect(first.currencyCode == "INR")
        first.name = "Spare Cash"
        first.amountText = "10"
        #expect(first.save() != nil)
        #expect(fake.savedDrafts.count == 1)
    }
}
