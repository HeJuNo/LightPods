import Foundation

/// Speed Tap drill: all pods light up, tap as many as you can in the time limit.
class SpeedTapDrill: Drill {
    let name = "Speed Tap"
    let description = "Tap as many lit pods as you can before time runs out!"
    let minPods = 1
    let maxPods: Int? = nil
    let playerRange: ClosedRange<Int> = 1...6
    let iconName = "flame.fill"
    let stats: DrillStats
    let config: DrillConfiguration

    init(config: DrillConfiguration = DrillConfiguration()) {
        self.config = config
        self.stats = DrillStats(drillName: "Speed Tap")
    }

    func run(engine: DrillEngine) async {
        let color = config.players.first?.podColor ?? .white
        let adjusted = config.adjustedRGB(for: color)
        let durationSeconds = config.durationTimeMinutes * 60.0

        for cycle in 0..<config.cycleCount {
            guard !Task.isCancelled else { break }
            if cycle > 0 {
                try? await Task.sleep(for: .seconds(config.timeBetweenCycles))
            }

            // Light all pods
            engine.drainTaps()
            for pod in engine.pods {
                engine.setColor(pod, r: adjusted.r, g: adjusted.g, b: adjusted.b, offOnTap: true)
            }

            let deadline = Date().addingTimeInterval(durationSeconds)

            while !Task.isCancelled && Date() < deadline {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { break }

                if let (pod, event) = await engine.waitForAnyLitTap(timeout: remaining) {
                    stats.hits += 1
                    stats.reactionTimesMs.append(event.elapsedMs)

                    // Re-light the tapped pod
                    try? await Task.sleep(for: .milliseconds(100))
                    if !Task.isCancelled {
                        engine.setColor(pod, r: adjusted.r, g: adjusted.g, b: adjusted.b, offOnTap: true)
                    }
                }
            }

            engine.allOff()
        }
    }
}
