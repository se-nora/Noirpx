import XCTest

/// Returns true when the slow tier is explicitly opted in via environment.
/// Reads ProcessInfo on each call (cheap; no caching needed).
@inline(__always)
func isSlowTestTierEnabled() -> Bool {
    ProcessInfo.processInfo.environment["NOIRPX_SLOW_TESTS"] == "1"
}

/// Skip the current test unless the slow tier is enabled.
/// Uses XCTSkip so skipped tests appear in xUnit output with "skipped" status.
/// Call with `try skipUnlessSlowTier()` at every slow test entry point.
func skipUnlessSlowTier(_ message: String = "Slow-tier test; run with NOIRPX_SLOW_TESTS=1") throws {
    if !isSlowTestTierEnabled() { throw XCTSkip(message) }
}