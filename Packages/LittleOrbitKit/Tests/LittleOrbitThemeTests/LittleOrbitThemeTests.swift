import XCTest
@testable import LittleOrbitTheme

final class LittleOrbitThemeTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(LittleOrbitTheme.moduleName, "LittleOrbitTheme")
    }
}
