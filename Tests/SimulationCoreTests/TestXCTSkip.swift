import XCTest

final class TestXCTSkip: XCTestCase {
    func testSkip() throws {
        throw XCTSkip("Test skip")
    }
    
    func testNoSkip() throws {
        XCTAssertTrue(true)
    }
}
