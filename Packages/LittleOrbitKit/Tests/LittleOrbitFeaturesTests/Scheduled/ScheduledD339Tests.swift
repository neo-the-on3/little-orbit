import Foundation
import LittleOrbitDomain
import Testing

@testable import LittleOrbitFeatures

/// D339 and UI Designer's re-review: the noun-free Skip title on both platforms, the Mac list footer for automatic
/// items, the unchanged iOS footnote, and the type control's VoiceOver label. Made-up data.
@MainActor
@Suite("Scheduled D339 copy and UI Designer's fixes")
struct ScheduledD339Tests {
    @Test("Skip's title has no type noun, the same on iOS and the Mac, for income too")
    func skipTitle() throws {
        let scene = try ScheduledScene()
        var salary = scene.item("Salary", day: 15, month: 10)
        salary.type = .income
        salary.categoryID = nil
        try scene.add(salary)
        for platform in [ScheduledPlatform.iOS, .macOS] {
            let list = ScheduledListViewModel(
                useCases: scene.useCases,
                locale: Locale(identifier: "en_IN"),
                platform: platform,
            )
            list.load()
            list.confirmSkip(try #require(list.overdueRows.first))
            #expect(list.confirmation?.title == "Skip 15 Oct Salary?")
            #expect(list.confirmation?.isDestructive == false)
        }
    }

    @Test("The Mac list has the automatic footer when it shows an automatic item; iOS keeps the form footnote")
    func footers() throws {
        let scene = try ScheduledScene()
        try scene.add(scene.item("Gym", day: 18, month: 10))
        let mac = ScheduledListViewModel(
            useCases: scene.useCases,
            locale: Locale(identifier: "en_IN"),
            platform: .macOS,
        )
        mac.load()
        #expect(mac.automaticFooter == nil)
        try scene.add(scene.item("Rent", day: 1, automatic: true, month: 11))
        mac.load()
        #expect(
            mac.automaticFooter
                == "Automatic items are recorded on the due date, or the next time little-orbit opens, once each."
        )
        let phone = ScheduledListViewModel(
            useCases: scene.useCases,
            locale: Locale(identifier: "en_IN"),
            platform: .iOS,
        )
        phone.load()
        #expect(phone.automaticFooter == nil)
        phone.openNew()
        let form = try #require(phone.form)
        #expect(
            form.automaticFootnote == "Automatic items are recorded on the due date, or when you next open the app."
        )
        #expect(form.typeLabel == "Type")
    }
}
