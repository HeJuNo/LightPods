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
    let config: DrillConfiguration

    init(config: DrillConfiguration = DrillConfiguration()) {
        self.config = config
        self.stats = DrillStats(drillName: "Reaction Time")
    }

    func run(engine: DrillEngine) async {
        guard let pod = engine.pods.first else { return }
        let greenAdj = config.adjustedRGB(for: .green)
        let redAdj = config.adjustedRGB(for: .red)

        for cycle in 0..<config.cycleCount {
            guard !Task.isCancelled else { break }
            if cycle > 0 {
                try? await Task.sleep(for: .seconds(config.timeBetweenCycles))
            }

            let attempts = config.durationHitCount
            for _ in 0..<attempts {
                guard !Task.isCancelled else { break }

                // Red = get ready
                engine.setColor(pod, r: redAdj.r, g: redAdj.g, b: redAdj.b)
                engine.drainTaps()

                // Random delay
                let delay = Double.random(in: 2.0...5.0)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { break }

                // Green = go!
                engine.setColor(pod, r: greenAdj.r, g: greenAdj.g, b: greenAdj.b, offOnTap: true)

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
}
