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

    let length: Int
    let timeoutSeconds: Double
    let color: PodColor

    init(length: Int = 8, timeoutSeconds: Double = 5.0, color: PodColor = .blue) {
        self.length = length
        self.timeoutSeconds = timeoutSeconds
        self.color = color
        self.stats = DrillStats(drillName: "Sequence")
    }

    func run(engine: DrillEngine) async {
        // Build a random sequence
        let sequence: [PodDevice] = (0..<length).compactMap { _ in
            engine.randomPod()
        }

        for (i, target) in sequence.enumerated() {
            guard !Task.isCancelled else { break }

            engine.drainTaps()
            engine.setColor(target, color: color, offOnTap: true)

            if let event = await engine.waitForTap(from: target, timeout: timeoutSeconds, stats: stats) {
                stats.hits += 1
                stats.reactionTimesMs.append(event.elapsedMs)
            } else {
                stats.misses += 1
                engine.turnOff(target)
                stats.notes.append("Step \(i + 1): timeout on \(target.name)")
            }

            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}
