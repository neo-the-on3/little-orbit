import XCTest

@testable import LittleOrbitDomain

final class LittleOrbitDomainTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertEqual(LittleOrbitDomain.moduleName, "LittleOrbitDomain")
    }
}
