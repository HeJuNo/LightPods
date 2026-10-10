import Foundation

/// Reaction Time drill: classic reaction test.
/// Pod goes red → random delay → green → measure tap time.
class ReactionTimeDrill: Drill {
    let name = "Reaction Time"
    let description = "Wait for green, then tap as fast as you can!"
    let minPods = 1
    let maxPods: Int? = 1
    let playerRange: ClosedRange<Int> = 1...1
    let iconName = "timer"
    let stats: DrillStats

    let attempts: Int
    let minDelaySeconds: Double
    let maxDelaySeconds: Double

    init(attempts: Int = 5, minDelay: Double = 2.0, maxDelay: Double = 5.0) {
        self.attempts = attempts
        self.minDelaySeconds = minDelay
        self.maxDelaySeconds = maxDelay
        self.stats = DrillStats(drillName: "Reaction Time")
    }

    func run(engine: DrillEngine) async {
        guard let pod = engine.pods.first else { return }

        for _ in 0..<attempts {
            guard !Task.isCancelled else { break }

            // Red = get ready
            engine.setColor(pod, color: .red)
            engine.drainTaps()

            // Random delay
            let delay = Double.random(in: minDelaySeconds...maxDelaySeconds)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { break }

            // Green = go!
            engine.setColor(pod, color: .green, offOnTap: true)

            if let event = await engine.waitForTap(from: pod, timeout: 10.0, stats: stats) {
                stats.hits += 1
                stats.reactionTimesMs.append(event.elapsedMs)
            } else {
                stats.misses += 1
            }

            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}
