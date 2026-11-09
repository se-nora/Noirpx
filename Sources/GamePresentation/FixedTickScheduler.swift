/// Converts host-provided monotonic timestamps into fixed simulation steps.
public struct FixedTickScheduler {
    private let interval: Double
    private let maximumSteps: Int
    private var previousTime: Double?
    private var accumulated = 0.0

    public init(ticksPerSecond: Double = 60, maximumSteps: Int = 4) {
        precondition(ticksPerSecond.isFinite && ticksPerSecond > 0)
        precondition(maximumSteps > 0)
        interval = 1 / ticksPerSecond
        self.maximumSteps = maximumSteps
    }

    /// Clears the timing baseline and any unprocessed time on lifecycle changes.
    public mutating func reset() {
        previousTime = nil
        accumulated = 0
    }

    public mutating func steps(at time: Double) -> Int {
        precondition(time.isFinite)
        guard let previousTime else {
            self.previousTime = time
            return 0
        }
        guard time >= previousTime else {
            reset()
            self.previousTime = time
            return 0
        }
        self.previousTime = time
        accumulated += time - previousTime
        let tolerance = max(time.ulp, previousTime.ulp) * 2
        let available = ((accumulated + tolerance) / interval).rounded(.down)
        let steps = available >= Double(maximumSteps) ? maximumSteps : Int(available)
        // Drop excess elapsed time instead of skipping simulation ticks.
        if available > Double(maximumSteps) {
            accumulated.formTruncatingRemainder(dividingBy: interval)
            if accumulated + tolerance >= interval {
                accumulated = 0
            }
        } else {
            accumulated = max(0, accumulated - Double(steps) * interval)
        }
        return steps
    }
}
