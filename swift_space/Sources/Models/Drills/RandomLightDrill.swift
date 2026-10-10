import Foundation

/// Random Light drill: light one random pod, time the tap, repeat.
/// This is the basic reaction training drill.
class RandomLightDrill: Drill {
    let name = "Random Light"
    let description = "Tap each pod as fast as you can. Pods light up randomly."
    let minPods = 1
    let maxPods: Int? = nil
    let playerRange: ClosedRange<Int> = 1...1
    let iconName = "bolt.fill"
    let stats: DrillStats

    let rounds: Int
    let timeoutSeconds: Double
    let color: PodColor

    init(rounds: Int = 10, timeoutSeconds: Double = 5.0, color: PodColor = .white) {
        self.rounds = rounds
        self.timeoutSeconds = timeoutSeconds
        self.color = color
        self.stats = DrillStats(drillName: "Random Light")
    }

    func run(engine: DrillEngine) async {
        var lastPod: PodDevice? = nil

        for round in 0..<rounds {
            guard !Task.isCancelled else { break }

            guard let target = engine.randomPod(excluding: lastPod) else { break }
            lastPod = target

            engine.drainTaps()
            engine.setColor(target, color: color, offOnTap: true)

            if let event = await engine.waitForTap(from: target, timeout: timeoutSeconds, stats: stats) {
                stats.hits += 1
                stats.reactionTimesMs.append(event.elapsedMs)
            } else {
                stats.misses += 1
                engine.turnOff(target)
                stats.notes.append("Round \(round + 1): timeout on \(target.name)")
            }

            // Brief pause between rounds
            try? await Task.sleep(for: .milliseconds(300))
        }
    }
}
