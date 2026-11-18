/// Pure percentile computation for benchmark sample analysis.
///
/// All functions are pure: they sort a copy of the input and never read
/// wall-clock time, randomness, or platform state, so results are fully
/// deterministic for a given input array.
public struct Metrics {
    public init() {}

    /// Returns the p50, p95, and max of `values` after sorting ascending.
    ///
    /// - p50 is the element at 0-based index `count / 2`.
    /// - p95 is the element at 0-based index `Int(Double(count) * 0.95)`.
    /// - max is the last element.
    ///
    /// Both percentile indices are clamped to a valid range `[0, count - 1]`,
    /// so small samples (including a single sample) always resolve to index 0.
    public static func percentiles(_ values: [UInt64]) -> (p50: UInt64, p95: UInt64, max: UInt64) {
        guard !values.isEmpty else {
            return (0, 0, 0)
        }
        let sorted = values.sorted()
        let count = sorted.count
        let p50Index = min(max(count / 2, 0), count - 1)
        let p95Index = min(max(Int(Double(count) * 0.95), 0), count - 1)
        return (sorted[p50Index], sorted[p95Index], sorted[count - 1])
    }
}
