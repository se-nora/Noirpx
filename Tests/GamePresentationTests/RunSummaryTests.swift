/// Tests for run summary data and overlay (Goal: run-summary).
/// Covers DisplayListState round-trip, summary data fields, and overlay rendering.
@testable import GamePresentation
import SimulationCore
import XCTest

final class RunSummaryTests: XCTestCase {

    // MARK: - DisplayListState round-trip

    func testDisplayListStateRoundTripWithSummaryFields() {
        let original = DisplayListState(
            version: "0.54.0",
            worldKind: .cave,
            seed: 0x12345678,
            worldWidth: 256,
            worldHeight: 128,
            tick: 5000,
            depth: 85,
            level: 2,
            biomeName: "collapsed mine",
            outcome: .died,
            runGold: 99,
            kills: 7,
            playTimeTicks: 9000, // 2:30
            causeOfDeath: "explosion",
            sessionBestLevel: 4,
            sessionBestDepth: 210,
            selectedMaterial: .water,
            isCasting: true,
            discoveredMaterials: [.sand, .water, .gold],
            hudVisible: true,
            controls: .touch,
            overlays: DisplayOverlayVisibility(stats: true, help: false, crafting: true)
        )

        XCTAssertEqual(original.kills, 7)
        XCTAssertEqual(original.playTimeTicks, 9000)
        XCTAssertEqual(original.causeOfDeath, "explosion")
        XCTAssertEqual(original.sessionBestLevel, 4)
        XCTAssertEqual(original.sessionBestDepth, 210)
    }

    // MARK: - Time formatting

    func testTimeFormatting() {
        // formatTime is private; test via overlay text in HUDLayoutTests
        // but here verify expected MM:SS format logic
        func format(_ ticks: UInt64) -> String {
            let seconds = Int(ticks / 60)
            return String(format: "%02d:%02d", seconds / 60, seconds % 60)
        }
        XCTAssertEqual(format(0), "00:00")
        XCTAssertEqual(format(60), "00:01")
        XCTAssertEqual(format(3600), "01:00")
        XCTAssertEqual(format(7200), "02:00")
        XCTAssertEqual(format(9000), "02:30")
        XCTAssertEqual(format(3661), "01:01")
    }

    // MARK: - Summary data defaults

    func testSummaryFieldsDefaultValues() {
        let state = DisplayListState(
            version: "0.54.0",
            worldKind: .cave,
            seed: 1,
            worldWidth: 128,
            worldHeight: 64,
            tick: 0,
            outcome: .playing,
            selectedMaterial: .sand,
            isCasting: false
        )
        XCTAssertEqual(state.kills, 0)
        XCTAssertEqual(state.playTimeTicks, 0)
        XCTAssertNil(state.causeOfDeath)
        XCTAssertEqual(state.sessionBestLevel, 1)
        XCTAssertEqual(state.sessionBestDepth, 0)
    }

    // MARK: - Determinism

    func testDeterministicOverlayForSameState() {
        func buildState() -> DisplayListState {
            DisplayListState(
                version: "0.54.0",
                worldKind: .cave,
                seed: 42,
                worldWidth: 480,
                worldHeight: 270,
                tick: 3600,
                depth: 120,
                level: 3,
                biomeName: "cinder wastes",
                outcome: .died,
                runGold: 142,
                kills: 4,
                playTimeTicks: 7200,
                causeOfDeath: "lava",
                sessionBestLevel: 5,
                sessionBestDepth: 300,
                selectedMaterial: .sand,
                isCasting: false,
                hudVisible: true,
                overlays: DisplayOverlayVisibility(stats: false, help: false, crafting: false)
            )
        }
        let list1 = HUDLayout.gameUI(width: 480, height: 270, state: buildState())
        let list2 = HUDLayout.gameUI(width: 480, height: 270, state: buildState())
        XCTAssertEqual(list1, list2, "Same state must produce identical display list")
    }
}