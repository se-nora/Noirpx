import XCTest
@testable import GamePresentation
import SimulationCore

@MainActor
final class MaterialDiscoveryTests: XCTestCase {
    func testObserveUnionsNewMaterials() {
        let discovery = MaterialDiscovery(initially: [.sand])
        discovery.observe([.water, .fire, .sand]) // sand already known
        XCTAssertEqual(discovery.discovered, [.sand, .water, .fire])
    }

    func testObserveEmptyIsNoOp() {
        let discovery = MaterialDiscovery(initially: [.sand])
        discovery.observe([])
        XCTAssertEqual(discovery.discovered, [.sand])
    }

    func testSelectableIsDiscoveredIntersectDrawable() {
        let discovery = MaterialDiscovery(initially: [.sand, .water, .empty])
        // .empty is never drawable, so it's excluded from selectable
        XCTAssertEqual(discovery.selectable, [.sand, .water])
        XCTAssertTrue(discovery.isSelectable(.sand))
        XCTAssertFalse(discovery.isSelectable(.empty))
        XCTAssertFalse(discovery.isSelectable(.lava)) // not discovered
    }

    func testSelectableCoversAllDrawableWhenFullyDiscovered() {
        let discovery = MaterialDiscovery(initially: Set(MaterialBrush.drawable))
        XCTAssertEqual(discovery.selectable, Set(MaterialBrush.drawable))
        // Every drawable material (all Material cases except .empty) is selectable
        for material in SimulationCore.Material.allCases where material != .empty {
            XCTAssertTrue(discovery.isSelectable(material))
        }
    }
}
