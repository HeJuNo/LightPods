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
    let config: DrillConfiguration

    init(config: DrillConfiguration = DrillConfiguration()) {
        self.config = config
        self.stats = DrillStats(drillName: "Color Match")
    }

    func run(engine: DrillEngine) async {
        let targetColor: PodColor = .green
        let distractorColor: PodColor = .red
        let targetAdj = config.adjustedRGB(for: targetColor)
        let distractorAdj = config.adjustedRGB(for: distractorColor)
        let timeout = config.timeoutSeconds ?? 5.0

        for cycle in 0..<config.cycleCount {
            guard !Task.isCancelled else { break }
            if cycle > 0 {
                try? await Task.sleep(for: .seconds(config.timeBetweenCycles))
            }

            let rounds = config.durationHitCount
            for _ in 0..<rounds {
                guard !Task.isCancelled else { break }

                guard let target = engine.randomPod() else { break }

                await config.lightDelay()
                engine.drainTaps()

                // Light all pods: target gets target color, rest get distractor
                for pod in engine.pods {
                    if pod.id == target.id {
                        engine.setColor(pod, r: targetAdj.r, g: targetAdj.g, b: targetAdj.b, offOnTap: true)
                    } else {
                        engine.setColor(pod, r: distractorAdj.r, g: distractorAdj.g, b: distractorAdj.b, offOnTap: true)
                    }
                }

                if let (src, event) = await engine.waitForAnyLitTap(timeout: timeout) {
                    if src.id == target.id {
                        stats.hits += 1
                        stats.reactionTimesMs.append(event.elapsedMs)
                    } else {
                        stats.misses += 1
                    }
                } else {
                    stats.misses += 1
                }

                engine.allOff()
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }
}
