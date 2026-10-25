import Foundation
import LittleOrbitDomain
import Testing

/// The Scheduled form's "Create “‹name›”" row (#197, #23): picking it creates the payee, or reuses one with the same
/// name, ignoring case and outer spaces.
@MainActor
@Suite("Scheduled form payee creation (#197)")
struct ScheduledPayeeCreationTests {
    private typealias Fix = ScheduledFixture

    @Test("A new name is saved as a payee once, trimmed")
    func createsPayee() throws {
        let repository = FakeScheduleRepository()
        let payee = try #require(try repository.useCases().createPayee(named: "  Gym Co  "))
        #expect(payee.name == "Gym Co")
        #expect(repository.snapshot.payees.filter { $0.name == "Gym Co" }.count == 1)
        #expect(repository.saves == 1)
    }

    @Test("An existing payee's name, in any case, is that payee; nothing is saved")
    func reusesExisting() throws {
        let repository = FakeScheduleRepository()
        let payee = try #require(try repository.useCases().createPayee(named: "corner bakery"))
        #expect(payee.id == Fix.bakeryID)
        #expect(repository.saves == 0)
        #expect(repository.snapshot.payees.count == 1)
    }

    @Test("A blank name creates nothing")
    func blank() throws {
        let repository = FakeScheduleRepository()
        #expect(try repository.useCases().createPayee(named: "   ") == nil)
        #expect(repository.saves == 0)
    }
}
