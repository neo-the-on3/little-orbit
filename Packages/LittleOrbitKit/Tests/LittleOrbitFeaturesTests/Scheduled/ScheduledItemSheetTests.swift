import Foundation
import LittleOrbitDomain
import LittleOrbitFeatures
import LittleOrbitPersistence
import Testing

/// The item screen a scheduled history row opens in a sheet starts on a new list model: until that model has read
/// the listing, the item isn't missing, so the screen mustn't close as if it had been deleted (Tester's #203 iOS
/// FAIL).
@MainActor
@Suite("Scheduled item sheet (S85, #203)")
struct ScheduledItemSheetTests {
    @Test("An item a new model hasn't loaded yet isn't gone; after loading it shows")
    func notLoadedIsNotGone() throws {
        let scene = try ScheduledScene()
        let rent = scene.item("Rent", day: 1, month: 11)
        try scene.add(rent)
        let list = scene.feature().makeList()
        #expect(list.detail(rent.id) == nil)
        #expect(!list.isGone(rent.id))

        list.loadIfNeeded()
        #expect(list.detail(rent.id) != nil)
        #expect(!list.isGone(rent.id))
    }

    @Test("An item deleted after loading is gone, so its screen closes")
    func deletedIsGone() throws {
        let scene = try ScheduledScene()
        let rent = scene.item("Rent", day: 1, month: 11)
        try scene.add(rent)
        let list = scene.feature().makeList()
        list.load()
        try scene.repository.deleteScheduledItem(id: rent.id)
        list.load()
        #expect(list.detail(rent.id) == nil)
        #expect(list.isGone(rent.id))
    }

    @Test("loadIfNeeded reads the listing once; later changes come through load")
    func loadIfNeededOnce() throws {
        let scene = try ScheduledScene()
        let rent = scene.item("Rent", day: 1, month: 11)
        try scene.add(rent)
        let list = scene.feature().makeList()
        list.loadIfNeeded()
        let gym = scene.item("Gym", day: 5, month: 11)
        try scene.add(gym)
        list.loadIfNeeded()
        #expect(list.detail(gym.id) == nil)
        list.load()
        #expect(list.detail(gym.id) != nil)
    }
}
