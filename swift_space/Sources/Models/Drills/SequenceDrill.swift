import Foundation

/// Sequence drill: tap pods in the order they light up.
class SequenceDrill: Drill {
    let name = "Sequence"
    let description = "Pods light up one by one. Tap each in order."
    let minPods = 2
    let maxPods: Int? = nil
    let playerRange: ClosedRange<Int> = 1...1
    let iconName = "arrow.right.arrow.left"
    let stats: DrillStats
    let config: DrillConfiguration

    init(config: DrillConfiguration = DrillConfiguration()) {
        self.config = config
        self.stats = DrillStats(drillName: "Sequence")
    }

    func run(engine: DrillEngine) async {
        let color = config.players.first?.podColor ?? .blue
        let adjusted = config.adjustedRGB(for: color)
        let length = config.durationHitCount
        let timeout = config.timeoutSeconds ?? 5.0

        for cycle in 0..<config.cycleCount {
            guard !Task.isCancelled else { break }
            if cycle > 0 {
                try? await Task.sleep(for: .seconds(config.timeBetweenCycles))
            }

            let sequence: [PodDevice] = (0..<length).compactMap { _ in
                engine.randomPod()
            }

            for (i, target) in sequence.enumerated() {
                guard !Task.isCancelled else { break }

                await config.lightDelay()
                engine.drainTaps()
                engine.setColor(target, r: adjusted.r, g: adjusted.g, b: adjusted.b,
                                offOnTap: config.offOnTap)

                if let event = await engine.waitForTap(from: target, timeout: timeout, stats: stats) {
                    stats.hits += 1
                    stats.reactionTimesMs.append(event.elapsedMs)
                } else {
                    stats.misses += 1
                    engine.turnOff(target)
                    stats.notes.append("Step \(i + 1): timeout on \(target.name)")
                }
            }
        }
    }
}
