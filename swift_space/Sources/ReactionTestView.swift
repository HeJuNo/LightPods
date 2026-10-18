import BlazePodKit
import SwiftUI

/// Minimal "light a random pod, measure the hit" loop to exercise light + touch end to end.
final class ReactionTest: ObservableObject {
    struct Round: Identifiable {
        let id = UUID()
        let podName: String
        let color: PodColor
        let reactionMs: Int?   // nil = miss
    }

    @Published private(set) var rounds: [Round] = []
    @Published private(set) var isRunning = false
    @Published private(set) var activePod: String?
    @Published var roundCount = 10
    @Published var timeout: Double = 3
    @Published var offOnHit = true
    @Published var randomColors = true

    private weak var controller: PodController?
    private var current: (pod: BlazePod, color: PodColor)?
    private var lastPodID: UUID?
    private var pending: DispatchWorkItem?

    var hits: [Int] { rounds.compactMap(\.reactionMs) }
    var average: Int? { hits.isEmpty ? nil : hits.reduce(0, +) / hits.count }
    var best: Int? { hits.min() }
    var misses: Int { rounds.count - hits.count }

    func start(with controller: PodController) {
        guard !controller.readyPods.isEmpty else { return }
        self.controller = controller
        controller.allOff()
        controller.hitObserver = { [weak self] pod, ms in self?.handleHit(pod, ms) }
        rounds = []
        isRunning = true
        scheduleNext()
    }

    func stop() {
        pending?.cancel()
        current?.pod.lightOff()
        current = nil
        activePod = nil
        isRunning = false
        controller?.hitObserver = nil
    }

    private func scheduleNext() {
        guard isRunning else { return }
        guard rounds.count < roundCount else { return stop() }
        after(Double.random(in: 0.8...2.0)) { [weak self] in self?.lightRandomPod() }
    }

    private func lightRandomPod() {
        guard let controller, isRunning else { return }
        var candidates = controller.readyPods
        if candidates.count > 1 { candidates.removeAll { $0.id == lastPodID } }
        guard let pod = candidates.randomElement() else { return stop() }
        let color = randomColors ? PodColor.palette.randomElement()! : .default
        current = (pod, color)
        lastPodID = pod.id
        activePod = pod.name
        pod.lightOn(color, offOnHit: offOnHit)
        after(timeout) { [weak self] in self?.finishRound(reactionMs: nil) }
    }

    private func handleHit(_ pod: BlazePod, _ ms: Int) {
        guard let current, current.pod.id == pod.id else { return }
        finishRound(reactionMs: ms)
    }

    private func finishRound(reactionMs: Int?) {
        guard let current else { return }
        pending?.cancel()
        current.pod.lightOff()
        rounds.append(Round(podName: current.pod.name, color: current.color, reactionMs: reactionMs))
        self.current = nil
        activePod = nil
        scheduleNext()
    }

    private func after(_ seconds: Double, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

struct ReactionTestView: View {
    @EnvironmentObject private var controller: PodController
    @StateObject private var test = ReactionTest()

    var body: some View {
        NavigationStack {
            List {
                Section("Setup") {
                    LabeledContent("Ready pods", value: "\(controller.readyPods.count)")
                    Stepper("Rounds: \(test.roundCount)", value: $test.roundCount, in: 1...50)
                    Stepper("Timeout: \(test.timeout, specifier: "%.1f") s", value: $test.timeout, in: 1...10, step: 0.5)
                    Toggle("Random colours", isOn: $test.randomColors)
                    Toggle("Turn off on hit (fw ≥ 3.2)", isOn: $test.offOnHit)
                }
                .disabled(test.isRunning)

                Section {
                    if test.isRunning {
                        Button("Stop", role: .destructive) { test.stop() }
                        Text(test.activePod.map { "Hit \($0)!" } ?? "Get ready…")
                            .font(.title2.bold())
                    } else {
                        Button("Start") { test.start(with: controller) }
                            .disabled(controller.readyPods.isEmpty)
                    }
                }

                Section("Result") {
                    LabeledContent("Rounds", value: "\(test.rounds.count) / \(test.roundCount)")
                    LabeledContent("Average", value: test.average.map { "\($0) ms" } ?? "–")
                    LabeledContent("Best", value: test.best.map { "\($0) ms" } ?? "–")
                    LabeledContent("Misses", value: "\(test.misses)")
                }

                Section("Rounds") {
                    ForEach(test.rounds.reversed()) { round in
                        HStack {
                            Circle().fill(round.color.swatch).frame(width: 10, height: 10)
                            Text(round.podName)
                            Spacer()
                            Text(round.reactionMs.map { "\($0) ms" } ?? "miss")
                                .monospacedDigit()
                                .foregroundStyle(round.reactionMs == nil ? .red : .primary)
                        }
                    }
                }
            }
            .navigationTitle("Reaction test")
            .onDisappear { test.stop() }
        }
    }
}
