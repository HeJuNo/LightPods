import Foundation
import os.log

// MARK: - Drill Stats

/// Per-player statistics
@Observable
class PlayerDrillStats: Identifiable {
    let id = UUID()
    var playerName: String
    var playerColor: PodColor
    var reactionTimesMs: [UInt32] = []
    var hits: Int = 0
    var misses: Int = 0

    init(playerName: String, playerColor: PodColor) {
        self.playerName = playerName
        self.playerColor = playerColor
    }

    var attempts: Int { hits + misses }
    var accuracy: Double {
        guard attempts > 0 else { return 0 }
        return Double(hits) / Double(attempts)
    }
    var meanMs: Double {
        guard !reactionTimesMs.isEmpty else { return 0 }
        return Double(reactionTimesMs.reduce(0, { $0 + UInt64($1) })) / Double(reactionTimesMs.count)
    }
    var bestMs: UInt32? { reactionTimesMs.min() }
    var worstMs: UInt32? { reactionTimesMs.max() }
    var lastMs: UInt32? { reactionTimesMs.last }
}

/// Statistics collected during a drill session
@Observable
class DrillStats {
    var drillName: String
    var reactionTimesMs: [UInt32] = []
    var hits: Int = 0
    var misses: Int = 0
    var totalTimeMs: Int = 0
    var notes: [String] = []
    var playerStats: [PlayerDrillStats] = []
    var currentCycle: Int = 0
    var totalCycles: Int = 1

    init(drillName: String) {
        self.drillName = drillName
    }

    var attempts: Int { hits + misses }

    var accuracy: Double {
        guard attempts > 0 else { return 0 }
        return Double(hits) / Double(attempts)
    }

    var meanMs: Double {
        guard !reactionTimesMs.isEmpty else { return 0 }
        return Double(reactionTimesMs.reduce(0, { $0 + UInt64($1) })) / Double(reactionTimesMs.count)
    }

    var medianMs: Double {
        guard !reactionTimesMs.isEmpty else { return 0 }
        let sorted = reactionTimesMs.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return Double(sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return Double(sorted[mid])
    }

    var bestMs: UInt32? { reactionTimesMs.min() }
    var worstMs: UInt32? { reactionTimesMs.max() }
    var lastMs: UInt32? { reactionTimesMs.last }

    var hasMultiplePlayers: Bool { playerStats.count > 1 }
}

// MARK: - Drill Protocol

/// A drill is a self-contained game/exercise that controls pods and collects stats.
protocol Drill: AnyObject {
    /// Display name for the drill type
    var name: String { get }

    /// Short description
    var description: String { get }

    /// Minimum pods required
    var minPods: Int { get }

    /// Maximum pods supported (nil = unlimited)
    var maxPods: Int? { get }

    /// Player count range
    var playerRange: ClosedRange<Int> { get }

    /// SF Symbol for the drill
    var iconName: String { get }

    /// The stats being accumulated (observable for live UI updates)
    var stats: DrillStats { get }

    /// Run the drill. Called by DrillEngine on a Task — can use async/await.
    /// The drill should monitor `Task.isCancelled` and exit cleanly when cancelled.
    func run(engine: DrillEngine) async
}

// MARK: - Drill Engine

/// Runs a drill, manages tap routing, and provides pod control to drills.
@Observable
class DrillEngine {
    private let logger = Logger(subsystem: "com.hejuno.lightpods", category: "DrillEngine")

    /// The BLE manager to control pods through
    let bleManager: BLEManager

    /// The pods participating in this drill
    let pods: [PodDevice]

    /// Current drill being run
    private(set) var currentDrill: (any Drill)?

    /// Whether a drill is currently running
    var isRunning: Bool { currentDrill != nil }

    /// Tap queue — drills read taps from here
    private var tapContinuations: [CheckedContinuation<(PodDevice, TapEvent), Never>] = []
    private var tapBuffer: [(PodDevice, TapEvent)] = []

    /// Task running the current drill
    private var drillTask: Task<Void, Never>?

    /// Old tap callback to restore when drill ends
    private var previousTapCallback: ((PodDevice, TapEvent) -> Void)?

    init(bleManager: BLEManager, pods: [PodDevice]) {
        self.bleManager = bleManager
        self.pods = pods
    }

    /// Convenience: create with all authenticated pods
    convenience init(bleManager: BLEManager) {
        self.init(bleManager: bleManager, pods: bleManager.authenticatedPods)
    }

    // MARK: - Drill Lifecycle

    /// Start a drill
    func start(_ drill: any Drill) {
        guard !isRunning else {
            logger.warning("Cannot start drill: another drill is running")
            return
        }
        guard pods.count >= drill.minPods else {
            logger.error("Need at least \(drill.minPods) pods, have \(self.pods.count)")
            return
        }

        currentDrill = drill
        tapBuffer.removeAll()
        tapContinuations.removeAll()

        // Install tap handler
        previousTapCallback = bleManager.onTapReceived
        bleManager.onTapReceived = { [weak self] pod, event in
            self?.handleTap(pod: pod, event: event)
        }

        let startTime = DispatchTime.now()
        drillTask = Task { @MainActor [weak self] in
            guard let self else { return }
            logger.info("Drill '\(drill.name)' started with \(self.pods.count) pods")

            await drill.run(engine: self)

            let elapsed = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
            drill.stats.totalTimeMs = Int(elapsed / 1_000_000)

            // Clean up
            allOff()
            bleManager.onTapReceived = previousTapCallback
            previousTapCallback = nil
            currentDrill = nil
            tapContinuations.removeAll()
            tapBuffer.removeAll()
            logger.info("Drill '\(drill.name)' ended — hits=\(drill.stats.hits) misses=\(drill.stats.misses)")
        }
    }

    /// Stop the current drill
    func stop() {
        drillTask?.cancel()
        drillTask = nil
    }

    // MARK: - Pod Control (for drills to call)

    /// Set a pod's color
    func setColor(_ pod: PodDevice, r: UInt8, g: UInt8, b: UInt8, offOnTap: Bool = false) {
        bleManager.setColor(pod, r: r, g: g, b: b, offOnTap: offOnTap)
    }

    /// Set a pod's color using a preset
    func setColor(_ pod: PodDevice, color: PodColor, offOnTap: Bool = false) {
        bleManager.setColor(pod, color: color, offOnTap: offOnTap)
    }

    /// Turn off a pod
    func turnOff(_ pod: PodDevice) {
        bleManager.turnOff(pod)
    }

    /// Turn off all drill pods
    func allOff() {
        for pod in pods {
            bleManager.turnOff(pod)
        }
    }

    /// Drain any buffered taps (call before starting a timed section)
    func drainTaps() {
        tapBuffer.removeAll()
    }

    // MARK: - Tap Waiting (for drills)

    /// Wait for a tap from any pod in the drill. Returns nil if task is cancelled.
    func waitForTap(timeout: TimeInterval? = nil) async -> (PodDevice, TapEvent)? {
        // Check buffer first
        if !tapBuffer.isEmpty {
            return tapBuffer.removeFirst()
        }

        // Wait for next tap
        if let timeout = timeout {
            return await withTaskCancellation(timeout: timeout)
        } else {
            return await withCheckedContinuation { continuation in
                tapContinuations.append(continuation)
            }
        }
    }

    /// Wait for a tap specifically from the given pod. Other taps are counted as misses.
    func waitForTap(from pod: PodDevice, timeout: TimeInterval? = nil, stats: DrillStats) async -> TapEvent? {
        let deadline = timeout.map { Date().addingTimeInterval($0) }

        while !Task.isCancelled {
            let remaining = deadline.map { $0.timeIntervalSinceNow }
            if let remaining, remaining <= 0 { return nil }

            guard let (src, event) = await waitForTap(timeout: remaining) else {
                return nil
            }

            guard event.hitLitPod else { continue }

            if src.id == pod.id {
                return event
            } else {
                // Wrong pod tapped
                stats.misses += 1
            }
        }
        return nil
    }

    /// Wait for any lit-pod tap. Returns the pod and event.
    func waitForAnyLitTap(timeout: TimeInterval? = nil) async -> (PodDevice, TapEvent)? {
        let deadline = timeout.map { Date().addingTimeInterval($0) }

        while !Task.isCancelled {
            let remaining = deadline.map { $0.timeIntervalSinceNow }
            if let remaining, remaining <= 0 { return nil }

            guard let (src, event) = await waitForTap(timeout: remaining) else {
                return nil
            }

            if event.hitLitPod {
                return (src, event)
            }
        }
        return nil
    }

    // MARK: - Internal

    private func handleTap(pod: PodDevice, event: TapEvent) {
        // Only route taps from pods in this drill
        guard pods.contains(where: { $0.id == pod.id }) else { return }

        if !tapContinuations.isEmpty {
            let cont = tapContinuations.removeFirst()
            cont.resume(returning: (pod, event))
        } else {
            tapBuffer.append((pod, event))
        }
    }

    private func withTaskCancellation(timeout: TimeInterval) async -> (PodDevice, TapEvent)? {
        await withTaskGroup(of: (PodDevice, TapEvent)?.self) { group in
            group.addTask { @MainActor [weak self] in
                guard let self else { return nil }
                return await withCheckedContinuation { continuation in
                    self.tapContinuations.append(continuation)
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// Pick a random pod, avoiding the last one if possible
    func randomPod(excluding: PodDevice? = nil) -> PodDevice? {
        var candidates = pods
        if candidates.count > 1, let ex = excluding {
            candidates.removeAll { $0.id == ex.id }
        }
        return candidates.randomElement()
    }

    /// Pick a random pod from a subset, avoiding the last one if possible
    func randomPod(from subset: [PodDevice], excluding: PodDevice? = nil) -> PodDevice? {
        var candidates = subset
        if candidates.count > 1, let ex = excluding {
            candidates.removeAll { $0.id == ex.id }
        }
        return candidates.randomElement()
    }

    /// Divide pods into stations of the given size
    func assignStations(count: Int, podsPerStation: Int) -> [[PodDevice]] {
        let stationCount = min(count, max(1, pods.count / max(1, podsPerStation)))
        var stations: [[PodDevice]] = []
        var idx = 0
        for _ in 0..<stationCount {
            var station: [PodDevice] = []
            for _ in 0..<podsPerStation {
                if idx < pods.count {
                    station.append(pods[idx])
                    idx += 1
                }
            }
            if !station.isEmpty {
                stations.append(station)
            }
        }
        // Assign any remaining pods to existing stations round-robin
        while idx < pods.count {
            stations[idx % stations.count].append(pods[idx])
            idx += 1
        }
        return stations
    }
}
