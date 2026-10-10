import Foundation

/// Color Match drill: all pods light up, but only one is the target color.
/// Tap the correct (target-colored) pod.
class ColorMatchDrill: Drill {
    let name = "Color Match"
    let description = "Multiple pods light up. Tap only the target color!"
    let minPods = 2
    let maxPods: Int? = nil
    let playerRange: ClosedRange<Int> = 1...1
    let iconName = "paintpalette.fill"
    let stats: DrillStats

    let rounds: Int
    let timeoutSeconds: Double
    let targetColor: PodColor
    let distractorColor: PodColor

    init(rounds: Int = 10, timeoutSeconds: Double = 5.0,
         targetColor: PodColor = .green, distractorColor: PodColor = .red) {
        self.rounds = rounds
        self.timeoutSeconds = timeoutSeconds
        self.targetColor = targetColor
        self.distractorColor = distractorColor
        self.stats = DrillStats(drillName: "Color Match")
    }

    func run(engine: DrillEngine) async {
        for _ in 0..<rounds {
            guard !Task.isCancelled else { break }

            guard let target = engine.randomPod() else { break }

            engine.drainTaps()

            // Light all pods: target gets target color, rest get distractor
            for pod in engine.pods {
                if pod.id == target.id {
                    engine.setColor(pod, color: targetColor, offOnTap: true)
                } else {
                    engine.setColor(pod, color: distractorColor, offOnTap: true)
                }
            }

            // Wait for any lit tap
            if let (src, event) = await engine.waitForAnyLitTap(timeout: timeoutSeconds) {
                if src.id == target.id {
                    stats.hits += 1
                    stats.reactionTimesMs.append(event.elapsedMs)
                } else {
                    stats.misses += 1
                }
            } else {
                stats.misses += 1
                stats.notes.append("Timeout (target was \(target.name))")
            }

            engine.allOff()
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}
