import XCTest
@testable import LittleOrbitPersistence

final class LittleOrbitPersistenceTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(LittleOrbitPersistence.moduleName, "LittleOrbitPersistence")
    }
}
