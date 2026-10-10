import Foundation

/// Speed Tap drill: all pods light up, tap as many as you can in the time limit.
/// Each tapped pod re-lights immediately. Score = total hits.
class SpeedTapDrill: Drill {
    let name = "Speed Tap"
    let description = "Tap as many lit pods as you can before time runs out!"
    let minPods = 1
    let maxPods: Int? = nil
    let playerRange: ClosedRange<Int> = 1...6
    let iconName = "flame.fill"
    let stats: DrillStats

    let durationSeconds: Double
    let color: PodColor

    init(durationSeconds: Double = 30.0, color: PodColor = .white) {
        self.durationSeconds = durationSeconds
        self.color = color
        self.stats = DrillStats(drillName: "Speed Tap")
    }

    func run(engine: DrillEngine) async {
        // Light all pods
        engine.drainTaps()
        for pod in engine.pods {
            engine.setColor(pod, color: color, offOnTap: true)
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
                    engine.setColor(pod, color: color, offOnTap: true)
                }
            }
        }

        engine.allOff()
    }
}
