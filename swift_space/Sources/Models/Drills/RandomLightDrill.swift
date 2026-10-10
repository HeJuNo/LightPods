import Foundation

/// BlazePod-faithful Random drill.
///
/// **Random Logic:** One pod lights at a time (per station). On tap or timeout the
/// next pod activates randomly. Supports multi-player with per-player colors,
/// station layout, Regular and First-to-Hit competition modes, configurable
/// light delay, duration, cycles, start mode, and intensity.
///
/// Station layout:
///   - Pods are divided into `stationCount` stations of `podsPerStation` each.
///   - In **Regular** mode each station runs independently; players at that
///     station take turns. One random pod in the station lights in the current
///     player's color. On hit/timeout the next player's turn begins.
///   - In **First to Hit** mode one random pod lights globally (white/player-1
///     color). The first player to tap any lit pod scores the point. All
///     stations share one pod at a time.
class RandomLightDrill: Drill {
    let name = "Random"
    let description = "One pod lights at random. Tap it as fast as you can — supports multi-player stations and First-to-Hit."
    let minPods = 1
    let maxPods: Int? = nil
    let playerRange: ClosedRange<Int> = 1...6
    let iconName = "bolt.fill"
    let stats: DrillStats
    let config: DrillConfiguration

    init(config: DrillConfiguration = DrillConfiguration()) {
        self.config = config
        self.stats = DrillStats(drillName: "Random")
    }

    func run(engine: DrillEngine) async {
        // --- Setup per-player stats ---
        let playerConfigs = config.players.isEmpty
            ? [PlayerConfig.guest(index: 0, color: .white)]
            : config.players
        for pc in playerConfigs {
            stats.playerStats.append(
                PlayerDrillStats(playerName: pc.name, playerColor: pc.podColor)
            )
        }
        stats.totalCycles = config.cycleCount

        // --- Assign stations ---
        let stations = engine.assignStations(
            count: config.stationCount,
            podsPerStation: config.podsPerStation
        )
        guard !stations.isEmpty else { return }

        // --- Run cycles ---
        for cycle in 0..<config.cycleCount {
            guard !Task.isCancelled else { break }
            stats.currentCycle = cycle + 1

            if cycle > 0 {
                engine.allOff()
                try? await Task.sleep(for: .seconds(config.timeBetweenCycles))
            }

            if config.competitionMode == .firstToHit {
                await runFirstToHitCycle(engine: engine, stations: stations)
            } else {
                await runRegularCycle(engine: engine, stations: stations)
            }
        }
    }

    // MARK: - Regular Mode
    // Each station runs independently. Players rotate turns within each station.
    // One random pod per station lights in the current player's color.

    private func runRegularCycle(engine: DrillEngine, stations: [[PodDevice]]) async {
        // Start mode: wait for first hit before starting the timer
        if config.startMode == .startOnHit {
            guard let pod = engine.randomPod(from: stations[0]) else { return }
            let pc = config.players.first ?? PlayerConfig.guest(index: 0, color: .white)
            let adj = config.adjustedRGB(for: pc.podColor)
            engine.setColor(pod, r: adj.r, g: adj.g, b: adj.b, offOnTap: true)
            _ = await engine.waitForAnyLitTap(timeout: 120)
            engine.allOff()
        }

        let playerCount = stats.playerStats.count
        let timeLimit = durationTimeLimit()
        let hitTarget = config.durationHitCount
        let startTime = Date()
        var totalHits = 0
        var roundIndex = 0

        // Track last pod per station to avoid repeats
        var lastPods: [PodDevice?] = Array(repeating: nil, count: stations.count)

        while !Task.isCancelled {
            // --- Check end conditions ---
            if shouldEnd(totalHits: totalHits, hitTarget: hitTarget,
                         startTime: startTime, timeLimit: timeLimit) { break }

            // Current player (rotates through all players across rounds)
            let playerIndex = roundIndex % playerCount
            let pStats = stats.playerStats[playerIndex]
            let playerColor = pStats.playerColor
            let adj = config.adjustedRGB(for: playerColor)

            // Light one random pod in each station simultaneously
            var targets: [(station: Int, pod: PodDevice)] = []
            for (si, station) in stations.enumerated() {
                if let pod = engine.randomPod(from: station, excluding: lastPods[si]) {
                    targets.append((station: si, pod: pod))
                    lastPods[si] = pod
                }
            }

            // Apply light delay
            await config.lightDelay()
            guard !Task.isCancelled else { break }

            // Light all targets
            engine.drainTaps()
            for t in targets {
                engine.setColor(t.pod, r: adj.r, g: adj.g, b: adj.b,
                                offOnTap: config.offOnTap)
            }

            // Wait for any hit (or timeout)
            let timeout = config.timeoutSeconds ?? 30.0
            if let (src, event) = await engine.waitForAnyLitTap(timeout: timeout) {
                // Record hit
                let ms = event.elapsedMs
                pStats.hits += 1
                pStats.reactionTimesMs.append(ms)
                stats.hits += 1
                stats.reactionTimesMs.append(ms)
                totalHits += 1

                // Turn off remaining targets
                for t in targets where t.pod.id != src.id {
                    engine.turnOff(t.pod)
                }
            } else {
                // Timeout — count as miss
                pStats.misses += 1
                stats.misses += 1
                for t in targets {
                    engine.turnOff(t.pod)
                }
            }

            roundIndex += 1
        }
    }

    // MARK: - First to Hit Mode
    // One pod lights globally. All players compete — first tap wins the point.

    private func runFirstToHitCycle(engine: DrillEngine, stations: [[PodDevice]]) async {
        // Start mode
        if config.startMode == .startOnHit {
            guard let pod = engine.randomPod() else { return }
            let adj = config.adjustedRGB(for: .white)
            engine.setColor(pod, r: adj.r, g: adj.g, b: adj.b, offOnTap: true)
            _ = await engine.waitForAnyLitTap(timeout: 120)
            engine.allOff()
        }

        let timeLimit = durationTimeLimit()
        let hitTarget = config.durationHitCount
        let startTime = Date()
        var totalHits = 0
        var lastPod: PodDevice? = nil

        // In first-to-hit, light one pod per station simultaneously
        // (each station gets one pod in white / neutral color).
        // The player at the station that taps first scores.

        while !Task.isCancelled {
            if shouldEnd(totalHits: totalHits, hitTarget: hitTarget,
                         startTime: startTime, timeLimit: timeLimit) { break }

            // Light one random pod per station
            let adj = config.adjustedRGB(for: .white)
            var targets: [(station: Int, pod: PodDevice)] = []
            for (si, station) in stations.enumerated() {
                if let pod = engine.randomPod(from: station, excluding: si == 0 ? lastPod : nil) {
                    targets.append((station: si, pod: pod))
                }
            }

            await config.lightDelay()
            guard !Task.isCancelled else { break }

            engine.drainTaps()
            for t in targets {
                engine.setColor(t.pod, r: adj.r, g: adj.g, b: adj.b,
                                offOnTap: config.offOnTap)
            }

            let timeout = config.timeoutSeconds ?? 30.0
            if let (src, event) = await engine.waitForAnyLitTap(timeout: timeout) {
                let ms = event.elapsedMs
                lastPod = src

                // Determine which station was hit → which player scores
                let playerIdx: Int
                if let si = targets.firstIndex(where: { $0.pod.id == src.id }) {
                    playerIdx = si % stats.playerStats.count
                } else {
                    playerIdx = 0
                }
                let pStats = stats.playerStats[playerIdx]
                pStats.hits += 1
                pStats.reactionTimesMs.append(ms)
                stats.hits += 1
                stats.reactionTimesMs.append(ms)
                totalHits += 1

                // Turn off other lit pods
                for t in targets where t.pod.id != src.id {
                    engine.turnOff(t.pod)
                }
            } else {
                // Timeout — miss for all players
                for pStats in stats.playerStats {
                    pStats.misses += 1
                }
                stats.misses += 1
                for t in targets {
                    engine.turnOff(t.pod)
                }
            }
        }
    }

    // MARK: - Helpers

    private func durationTimeLimit() -> Double {
        switch config.durationMode {
        case .time, .timeOrHitCount:
            return config.durationTimeMinutes * 60.0
        case .hitCount:
            return Double.infinity
        }
    }

    private func shouldEnd(totalHits: Int, hitTarget: Int,
                           startTime: Date, timeLimit: Double) -> Bool {
        switch config.durationMode {
        case .hitCount:
            return totalHits >= hitTarget
        case .time:
            return Date().timeIntervalSince(startTime) >= timeLimit
        case .timeOrHitCount:
            return totalHits >= hitTarget || Date().timeIntervalSince(startTime) >= timeLimit
        }
    }
}
