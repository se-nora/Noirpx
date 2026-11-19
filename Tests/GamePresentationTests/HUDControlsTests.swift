#if canImport(SwiftUI)
import XCTest
import GamePresentation

@MainActor
final class HUDControlsTests: XCTestCase {
    func testEnergySegmentsHiddenWhenNil() {
        XCTAssertNil(HUDControls.energySegments(energy: nil, maxEnergy: 180))
        XCTAssertNil(HUDControls.energySegments(energy: nil, maxEnergy: nil))
    }

    func testEnergySegmentsCeilFillBoundaries() {
        let max = 180
        // 0 energy → 0 segments filled
        XCTAssertEqual(HUDControls.energySegments(energy: 0, maxEnergy: max), [false, false, false])
        // 1..60 → 1 segment (ceil fill: any nonzero energy shows at least one segment)
        XCTAssertEqual(HUDControls.energySegments(energy: 1, maxEnergy: max), [true, false, false])
        XCTAssertEqual(HUDControls.energySegments(energy: 59, maxEnergy: max), [true, false, false])
        XCTAssertEqual(HUDControls.energySegments(energy: 60, maxEnergy: max), [true, false, false])
        // 61..120 → 2 segments
        XCTAssertEqual(HUDControls.energySegments(energy: 61, maxEnergy: max), [true, true, false])
        XCTAssertEqual(HUDControls.energySegments(energy: 120, maxEnergy: max), [true, true, false])
        // 121..180 → 3 segments
        XCTAssertEqual(HUDControls.energySegments(energy: 121, maxEnergy: max), [true, true, true])
        XCTAssertEqual(HUDControls.energySegments(energy: 179, maxEnergy: max), [true, true, true])
        XCTAssertEqual(HUDControls.energySegments(energy: 180, maxEnergy: max), [true, true, true])
    }

    func testEnergySegmentsClampsToSegmentCount() {
        // Energy above max still shows 3 segments
        XCTAssertEqual(HUDControls.energySegments(energy: 200, maxEnergy: 180), [true, true, true])
        // Negative energy shows 0 segments
        XCTAssertEqual(HUDControls.energySegments(energy: -5, maxEnergy: 180), [false, false, false])
    }
}
#endif
