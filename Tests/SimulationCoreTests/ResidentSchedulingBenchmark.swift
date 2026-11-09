import Dispatch
import Foundation
import XCTest
import SimulationCore

final class ResidentSchedulingBenchmark: XCTestCase {
    func testSchedulingOverhead() throws {
        guard ProcessInfo.processInfo.environment["NOIRPX_BENCHMARK"] == "1" else {
            throw XCTSkip("Set NOIRPX_BENCHMARK=1 to run the scheduling microbenchmark.")
        }
        let samples = 100_000
        let clockStart = DispatchTime.now().uptimeNanoseconds
        var checksum: UInt64 = 0
        for _ in 0..<samples {
            checksum ^= DispatchTime.now().uptimeNanoseconds
        }
        let clockTime = DispatchTime.now().uptimeNanoseconds - clockStart
        print("clock_samples=\(samples) average_clock_ns=\(clockTime / UInt64(samples)) checksum=\(checksum)")
        let focus = CellPosition(x: 0, y: 0)
        for width in [16, 32, 64, 128] {
            var baseline = try ResidentSimulation(seed: 42, chunkWidth: width)
            for y in 0..<32 {
                for x in -16..<16 {
                    let position = CellPosition(x: x * width + width / 2, y: y * width + width / 2)
                    try baseline.enqueue(SimulationCommand(tick: 1, position: position, material: .sand))
                }
            }
            try baseline.advance(focus: focus) { false }
            var planning: [UInt64] = []
            var full: [UInt64] = []
            for _ in 0..<5 {
                var deferred = baseline
                var processed = baseline
                var start = DispatchTime.now().uptimeNanoseconds
                let deferredReport = try deferred.advance(focus: focus) { false }
                planning.append(DispatchTime.now().uptimeNanoseconds - start)
                start = DispatchTime.now().uptimeNanoseconds
                let fullReport = try processed.advance(focus: focus) { true }
                full.append(DispatchTime.now().uptimeNanoseconds - start)
                XCTAssertEqual(deferredReport.chunksConsidered, 1024)
                XCTAssertEqual(fullReport.chunksProcessed, 1024)
            }
            planning.sort()
            full.sort()
            print("width=\(width) chunks=1024 median_plan_ns=\(planning[2]) median_full_ns=\(full[2])")
        }
    }
}
