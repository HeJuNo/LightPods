import AudioToolbox
import BlazePodDrills
import BlazePodKit
import SwiftUI

/// Connects a `DrillSession` to the real pods and to SwiftUI.
final class DrillRunner: ObservableObject, DrillPodDriver {
    @Published private(set) var revision = 0
    @Published private(set) var lastEvent: DrillEvent?
    /// Increments on every hit, for haptics.
    @Published private(set) var hitTick = 0
    @Published private(set) var strikeTick = 0
    @Published private(set) var lostPod: String?

    private(set) var session: DrillSession!
    let definition: DrillDefinition
    /// Pods used by the drill, in station order.
    let pods: [BlazePod]
    private weak var controller: PodController?

    init(definition: DrillDefinition, controller: PodController, selection: [UUID]) {
        self.definition = definition
        self.controller = controller
        pods = controller.assignedPods(count: definition.totalPods, selection: selection)
        session = DrillSession(definition: definition, driver: self)
        session.onUpdate = { [weak self] in self?.revision += 1 }
        session.onEvent = { [weak self] in self?.handle($0) }
    }

    var phase: DrillPhase { session.phase }

    func start() {
        guard let controller else { return }
        controller.manager.workoutActive = true
        controller.hitObserver = { [weak self] pod, ms in self?.hit(pod, ms) }
        UIApplication.shared.isIdleTimerDisabled = true
        session.start()
    }

    func stop() {
        session.stop()
        finish()
    }

    private func finish() {
        controller?.hitObserver = nil
        controller?.manager.workoutActive = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: DrillPodDriver

    func light(pod: Int, color: PodColor, offOnHit: Bool) {
        if Demo.isOn {
            if definition.engine == .random || !definition.distractingColors.contains(color) { simulateHit(pod) }
            return
        }
        guard pods.indices.contains(pod) else { return }
        pods[pod].lightOn(color, offOnHit: offOnHit)
    }

    func off(pod: Int) {
        guard pods.indices.contains(pod) else { return }
        pods[pod].lightOff()
    }

    // MARK: Events

    private func hit(_ pod: BlazePod, _ ms: Int) {
        guard let i = pods.firstIndex(where: { $0.id == pod.id }) else { return }
        session.handleHit(pod: i, reactionMs: ms)
    }

    private func handle(_ event: DrillEvent) {
        lastEvent = event
        switch event {
        case .countdown:
            AudioServicesPlaySystemSound(1103)
        case .cycleStarted:
            AudioServicesPlaySystemSound(1113)
        case .hit:
            hitTick += 1
        case .strike:
            strikeTick += 1
            AudioServicesPlaySystemSound(1073)
        case .endingSoon:
            AudioServicesPlaySystemSound(1106)
        case .cycleEnded:
            break
        case .finished:
            AudioServicesPlaySystemSound(1114)
            finish()
        case .miss:
            break
        }
        // A pod that drops out during a drill can't be replaced; tell the user.
        if let gone = pods.first(where: { !$0.isReady }), lostPod == nil, session.phase != .finished {
            lostPod = gone.name
        }
    }

    /// Demo mode: a virtual athlete hits a lit pod after 300–900 ms.
    private func simulateHit(_ pod: Int) {
        let delay = Double.random(in: 0.3...0.9)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, session.litPods[pod] != nil else { return }
            // Mostly hit the right pod; a distracting pod now and then.
            let lit = session.litPods.keys.sorted()
            let target = Int.random(in: 0..<10) == 0 ? lit.randomElement() ?? pod : pod
            session.handleHit(pod: target, reactionMs: Int(delay * 1000))
        }
    }

    func podName(_ index: Int) -> String {
        pods.indices.contains(index) ? pods[index].name : "Pod \(index + 1)"
    }

    /// Short label for the pod map, e.g. "007" from "Pod 007".
    func podLabel(_ index: Int) -> String {
        let name = podName(index)
        return name.hasPrefix("Pod ") ? String(name.dropFirst(4)) : "\(index + 1)"
    }
}
