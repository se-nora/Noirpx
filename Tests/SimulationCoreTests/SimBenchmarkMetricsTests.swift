/// Unit tests for SimBenchmark.Metrics.percentiles.
import XCTest
import SimBenchmark

final class SimBenchmarkMetricsTests: XCTestCase {
    func testPercentilesSingleSampleResolvesToIndex0() {
        let result = Metrics.percentiles([42])
        XCTAssertEqual(result.p50, 42)
        XCTAssertEqual(result.p95, 42)
        XCTAssertEqual(result.max, 42)
    }

    func testPercentilesKnownArray() {
        // Sorted [10, 20, 30, 40, 50]: p50 index 2 -> 30, p95 index 4 -> 50, max 50.
        let result = Metrics.percentiles([10, 20, 30, 40, 50])
        XCTAssertEqual(result.p50, 30)
        XCTAssertEqual(result.p95, 50)
        XCTAssertEqual(result.max, 50)
    }

    func testPercentilesSortsUnsortedInput() {
        let result = Metrics.percentiles([50, 10, 30, 20, 40])
        XCTAssertEqual(result.p50, 30)
        XCTAssertEqual(result.p95, 50)
        XCTAssertEqual(result.max, 50)
    }

    func testPercentilesClampsIndicesToValidRange() {
        let result = Metrics.percentiles([7, 3])
        // count 2: sorted [3, 7]; p50 index 1 -> 7, p95 index Int(2*0.95)=1 -> 7, max 7.
        XCTAssertEqual(result.p50, 7)
        XCTAssertEqual(result.p95, 7)
        XCTAssertEqual(result.max, 7)
    }

    func testPercentilesSixHundredSamples() {
        let values = (1...600).map { UInt64($0) }
        let result = Metrics.percentiles(values)
        // count 600: p50 index 300 -> 301, p95 index Int(600*0.95)=570 -> 571, max 600.
        XCTAssertEqual(result.p50, 301)
        XCTAssertEqual(result.p95, 571)
        XCTAssertEqual(result.max, 600)
    }

    func testPercentilesEmptyReturnsZeros() {
        let result = Metrics.percentiles([])
        XCTAssertEqual(result.p50, 0)
        XCTAssertEqual(result.p95, 0)
        XCTAssertEqual(result.max, 0)
    }
}
