import Foundation
import os.log

@Observable
class DrillManager {
    private let logger = Logger(subsystem: "com.hejuno.lightpods", category: "Drill")

    var isRunning = false
    var currentPod: PodDevice?
    var totalHits: Int = 0
    var reactionTimes: [UInt32] = []

    var meanReactionTime: Double? {
        guard !reactionTimes.isEmpty else { return nil }
        return Double(reactionTimes.reduce(0, +)) / Double(reactionTimes.count)
    }

    var bestTime: UInt32? { reactionTimes.min() }
    var worstTime: UInt32? { reactionTimes.max() }
    var lastTime: UInt32? { reactionTimes.last }

    /// Pod IDs to use in the drill (empty = all authenticated)
    var activePodIDs: Set<UUID> = []

    private var bleManager: BLEManager?

    func start(bleManager: BLEManager, podIDs: Set<UUID> = []) {
        self.bleManager = bleManager
        self.activePodIDs = podIDs
        isRunning = true
        totalHits = 0
        reactionTimes = []
        currentPod = nil

        bleManager.onTapReceived = { [weak self] pod, state, ms in
            self?.handleTap(pod: pod, state: state, timeMs: ms)
        }

        lightNextPod()
        logger.info("Drill started with \(podIDs.isEmpty ? "all" : "\(podIDs.count)") pods")
    }

    func stop() {
        isRunning = false
        currentPod = nil
        bleManager?.onTapReceived = nil
        logger.info("Drill stopped")
    }

    func resetStats() {
        totalHits = 0
        reactionTimes = []
    }

    private func handleTap(pod: PodDevice, state: UInt8, timeMs: UInt32) {
        guard isRunning else { return }
        if state == 0x25 || state == 0x21 {
            totalHits += 1
            reactionTimes.append(timeMs)
            logger.info("Drill hit #\(self.totalHits): \(timeMs)ms")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.lightNextPod()
            }
        }
    }

    private func lightNextPod() {
        guard isRunning, let bleManager = bleManager else { return }

        var authenticatedPods = bleManager.connectedPods.filter { $0.connectionState == .authenticated }

        // Filter by active pod IDs if set
        if !activePodIDs.isEmpty {
            authenticatedPods = authenticatedPods.filter { activePodIDs.contains($0.id) }
        }

        guard !authenticatedPods.isEmpty else {
            logger.warning("No authenticated pods available for drill")
            stop()
            return
        }

        var candidates = authenticatedPods
        if candidates.count > 1, let current = currentPod {
            candidates.removeAll { $0.id == current.id }
        }

        guard let nextPod = candidates.randomElement() else { return }
        currentPod = nextPod
        bleManager.lightUp(nextPod, color: .white)
        logger.info("Lit pod \(nextPod.name)")
    }
}
