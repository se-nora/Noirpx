import XCTest
import SimulationCore

final class BeaconLegacyAPITests: XCTestCase {
    func testOriginalPublicConstantsRemainSourceCompatible() throws {
        let beacons: [CellPosition] = BeaconRun.beaconPositions
        let goal: CellPosition = BeaconRun.goalPosition
        let vent: ClosedRange<Int> = BeaconRun.ventX
        XCTAssertEqual(beacons, [.init(x: 22, y: 0), .init(x: 92, y: 0)])
        XCTAssertEqual(goal, .init(x: 130, y: 0))
        XCTAssertEqual(vent, 123...129)

        let defaultCourse = try BeaconRun().course
        XCTAssertEqual(defaultCourse.beacons, beacons)
        XCTAssertEqual(defaultCourse.goal, goal)
        XCTAssertEqual(defaultCourse.ventX, vent)

        let differentSeed = try XCTUnwrap((0..<1000).map(UInt64.init).first {
            let course = BeaconCourse(seed: $0)
            return course.beacons != beacons && course.goal != goal && course.ventX != vent
        })
        let generated = try BeaconRun(seed: differentSeed).course
        XCTAssertNotEqual(generated.beacons, beacons)
        XCTAssertNotEqual(generated.goal, goal)
        XCTAssertNotEqual(generated.ventX, vent)
    }
}
