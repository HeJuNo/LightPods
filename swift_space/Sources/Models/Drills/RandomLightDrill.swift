import Foundation

/// Random Light drill: light one random pod, time the tap, repeat.
class RandomLightDrill: Drill {
    let name = "Random Light"
    let description = "Tap each pod as fast as you can. Pods light up randomly."
    let minPods = 1
    let maxPods: Int? = nil
    let playerRange: ClosedRange<Int> = 1...1
    let iconName = "bolt.fill"
    let stats: DrillStats
    let config: DrillConfiguration

    init(config: DrillConfiguration = DrillConfiguration()) {
        self.config = config
        self.stats = DrillStats(drillName: "Random Light")
    }

    func run(engine: DrillEngine) async {
        let color = config.players.first?.podColor ?? .white
        let adjusted = config.adjustedRGB(for: color)

        for cycle in 0..<config.cycleCount {
            guard !Task.isCancelled else { break }
            if cycle > 0 {
                try? await Task.sleep(for: .seconds(config.timeBetweenCycles))
            }

            // Start mode
            if config.startMode == .startOnHit && cycle == 0 {
                guard let pod = engine.randomPod() else { return }
                engine.setColor(pod, r: adjusted.r, g: adjusted.g, b: adjusted.b, offOnTap: true)
                _ = await engine.waitForTap(from: pod, timeout: 60, stats: stats)
            }

            var lastPod: PodDevice? = nil
            let hitTarget = config.durationHitCount
            let timeLimit = config.durationMode == .time || config.durationMode == .timeOrHitCount
                ? config.durationTimeMinutes * 60.0 : Double.infinity
            let startTime = Date()
            var hitCount = 0

            while !Task.isCancelled {
                // Check end conditions
                if config.durationMode == .hitCount || config.durationMode == .timeOrHitCount {
                    if hitCount >= hitTarget { break }
                }
                if config.durationMode == .time || config.durationMode == .timeOrHitCount {
                    if Date().timeIntervalSince(startTime) >= timeLimit { break }
                }

                guard let target = engine.randomPod(excluding: lastPod) else { break }
                lastPod = target

                await config.lightDelay()
                guard !Task.isCancelled else { break }

                engine.drainTaps()
                engine.setColor(target, r: adjusted.r, g: adjusted.g, b: adjusted.b,
                                offOnTap: config.offOnTap)

                let timeout = config.timeoutSeconds ?? 30.0
                if let event = await engine.waitForTap(from: target, timeout: timeout, stats: stats) {
                    stats.hits += 1
                    stats.reactionTimesMs.append(event.elapsedMs)
                    hitCount += 1
                } else {
                    stats.misses += 1
                    engine.turnOff(target)
                }
            }
        }
    }
}
