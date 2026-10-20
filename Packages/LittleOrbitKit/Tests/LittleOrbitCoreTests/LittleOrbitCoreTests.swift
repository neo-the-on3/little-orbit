import XCTest

@testable import LittleOrbitCore

final class LittleOrbitCoreTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(LittleOrbitCore.moduleName, "LittleOrbitCore")
        XCTAssertFalse(LittleOrbitCore.placeholderTitle.isEmpty)
    }
}
