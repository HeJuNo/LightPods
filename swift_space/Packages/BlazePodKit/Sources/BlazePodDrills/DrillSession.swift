import BlazePodProtocol
import Foundation

/// What the engine needs from the pods. Pod indices are 0..<definition.totalPods;
/// station `s` owns pods `s * podsPerStation ..< (s + 1) * podsPerStation` (`ee.a` allocation).
public protocol DrillPodDriver: AnyObject {
    func light(pod: Int, color: PodColor, offOnHit: Bool)
    func off(pod: Int)
}

public struct DrillHit: Hashable, Sendable {
    public let reactionMs: Int
    public let cycle: Int
}

/// Per-player result (`fe.g`).
public struct PlayerStats: Hashable, Sendable {
    public var hits: [DrillHit] = []
    /// Pod went out on timeout while a hit was expected (`hitOrTimeout`), or lost a first-to-hit round.
    public var misses = 0
    /// Pod went out on timeout in `timeout` mode (expected, not a failure).
    public var timeouts = 0
    /// Hits on distracting pods (Focus).
    public var strikes = 0

    public var hitCount: Int { hits.count }
    public var averageMs: Int? { hits.isEmpty ? nil : hits.map(\.reactionMs).reduce(0, +) / hits.count }
    public var bestMs: Int? { hits.map(\.reactionMs).min() }
    public var slowestMs: Int? { hits.map(\.reactionMs).max() }
    public func hits(inCycle cycle: Int) -> Int { hits.filter { $0.cycle == cycle }.count }

    /// Share of lights answered with a hit.
    public var accuracy: Double? {
        let total = hits.count + misses + strikes
        return total == 0 ? nil : Double(hits.count) / Double(total)
    }
}

public struct DrillPlayer: Identifiable, Hashable, Sendable {
    public let station: Int
    public let index: Int
    public let colors: [PodColor]
    public internal(set) var stats = PlayerStats()

    public var id: String { "\(station)-\(index)" }
    public var primaryColor: PodColor { colors.first ?? .default }
}

public enum DrillPhase: Equatable, Sendable {
    case ready
    case countdown(Int)
    case running(cycle: Int)
    case resting(nextCycle: Int)
    case finished
}

public enum DrillEvent: Equatable, Sendable {
    case countdown(Int)
    case cycleStarted(Int)
    case hit(station: Int, player: Int, reactionMs: Int)
    case miss(station: Int, player: Int)
    case strike(station: Int, player: Int)
    /// 5 s left in a timed cycle (`ACTIVITY_WILL_END_IN_5_SEC`).
    case endingSoon
    case cycleEnded(Int)
    case finished
}

/// Runs a drill: countdown, cycles with rest, per-station engines, scoring.
///
/// Stations run their own engine on their own pods, as in the original. Cycles are kept in step:
/// a station that reaches the hit count goes dark until the other stations finish the cycle.
public final class DrillSession {
    public let definition: DrillDefinition
    public private(set) var phase: DrillPhase = .ready
    public private(set) var players: [DrillPlayer]
    /// Lit pods and their colours (for the live pod map).
    public private(set) var litPods: [Int: PodColor] = [:]
    public private(set) var cycleStartedAt: TimeInterval?
    public private(set) var restEndsAt: TimeInterval?
    public private(set) var stoppedEarly = false

    /// Called after any state change (main queue with the default scheduler).
    public var onUpdate: (() -> Void)?
    public var onEvent: ((DrillEvent) -> Void)?

    let scheduler: DrillScheduler
    private weak var driver: DrillPodDriver?
    var rng: any RandomNumberGenerator
    private let countdownSeconds: Int
    private var stations: [StationEngine] = []
    private var sessionTimers: [DrillTimer] = []

    public init(definition: DrillDefinition, driver: DrillPodDriver,
                scheduler: DrillScheduler = MainQueueScheduler(),
                rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
                countdown: Int = 3) {
        var def = definition
        def.normalize()
        self.definition = def
        self.driver = driver
        self.scheduler = scheduler
        self.rng = rng
        self.countdownSeconds = countdown
        players = (0..<def.stations).flatMap { s in
            (0..<def.playersPerStation).map { p in DrillPlayer(station: s, index: p, colors: def.colors(forPlayer: p)) }
        }
        stations = (0..<def.stations).map { s in
            let pods = Array(s * def.podsPerStation ..< (s + 1) * def.podsPerStation)
            switch def.engine {
            case .random: return RandomStation(station: s, pods: pods, session: self)
            case .focus: return FocusStation(station: s, pods: pods, session: self)
            }
        }
    }

    public var currentCycle: Int? {
        if case .running(let c) = phase { return c }
        return nil
    }

    /// Seconds elapsed in the running cycle.
    public var cycleElapsed: TimeInterval {
        cycleStartedAt.map { scheduler.now - $0 } ?? 0
    }

    /// Seconds left in a timed cycle.
    public var cycleRemaining: TimeInterval? {
        guard let total = definition.duration.seconds, cycleStartedAt != nil else { return nil }
        return max(0, Double(total) - cycleElapsed)
    }

    public var restRemaining: TimeInterval? {
        restEndsAt.map { max(0, $0 - scheduler.now) }
    }

    public func players(inStation s: Int) -> [DrillPlayer] { players.filter { $0.station == s } }

    // MARK: Control

    public func start() {
        guard phase == .ready else { return }
        tickCountdown(countdownSeconds)
    }

    /// Ends the drill immediately, keeping the results so far.
    public func stop() {
        guard phase != .finished else { return }
        stoppedEarly = phase != .ready
        cancelSessionTimers()
        stations.forEach { $0.stop() }
        allOff()
        cycleStartedAt = nil
        restEndsAt = nil
        phase = .finished
        emit(.finished)
    }

    /// Feed a touch from a pod (index into the drill's pod list).
    public func handleHit(pod: Int, reactionMs: Int) {
        guard case .running = phase else { return }
        stations.first { $0.pods.contains(pod) }?.handleHit(pod: pod, reactionMs: reactionMs)
    }

    // MARK: Phases

    private func tickCountdown(_ n: Int) {
        guard n > 0 else { return startCycle(1) }
        phase = .countdown(n)
        emit(.countdown(n))
        after(1) { [weak self] in self?.tickCountdown(n - 1) }
    }

    private func startCycle(_ cycle: Int) {
        cancelSessionTimers()
        restEndsAt = nil
        phase = .running(cycle: cycle)
        cycleStartedAt = scheduler.now
        emit(.cycleStarted(cycle))
        if let seconds = definition.duration.seconds {
            let total = Double(seconds)
            if total > 6 {
                after(total - 5) { [weak self] in self?.emit(.endingSoon) }
            }
            after(total) { [weak self] in self?.endCycle() }
        }
        stations.forEach { $0.start() }
        update()
    }

    /// Called by a station that reached the hit count (or strike-out).
    func stationFinished(_ station: StationEngine) {
        station.stop()
        if stations.allSatisfy(\.isDone) { endCycle() } else { update() }
    }

    private func endCycle() {
        guard case .running(let cycle) = phase else { return }
        cancelSessionTimers()
        stations.forEach { $0.stop() }
        allOff()
        cycleStartedAt = nil
        emit(.cycleEnded(cycle))
        if cycle >= definition.cycles {
            phase = .finished
            emit(.finished)
            return
        }
        phase = .resting(nextCycle: cycle + 1)
        restEndsAt = scheduler.now + Double(definition.cycleRest)
        let rest = Double(definition.cycleRest)
        // Count the last three seconds of the rest like the start countdown.
        for n in 1...3 where rest > Double(n) {
            after(rest - Double(n)) { [weak self] in self?.emit(.countdown(n)) }
        }
        after(rest) { [weak self] in self?.startCycle(cycle + 1) }
        update()
    }

    // MARK: Station callbacks

    func light(_ pod: Int, _ color: PodColor, offOnHit: Bool) {
        litPods[pod] = color
        driver?.light(pod: pod, color: color, offOnHit: offOnHit)
    }

    func off(_ pod: Int) {
        guard litPods.removeValue(forKey: pod) != nil else { return }
        driver?.off(pod: pod)
    }

    func recordHit(station: Int, player: Int, reactionMs: Int) -> Int {
        let cycle = currentCycle ?? 0
        let i = playerIndex(station, player)
        players[i].stats.hits.append(DrillHit(reactionMs: reactionMs, cycle: cycle))
        emit(.hit(station: station, player: player, reactionMs: reactionMs))
        return players[i].stats.hits(inCycle: cycle)
    }

    func recordMiss(station: Int, player: Int) {
        players[playerIndex(station, player)].stats.misses += 1
        emit(.miss(station: station, player: player))
    }

    func recordTimeout(station: Int, player: Int) {
        players[playerIndex(station, player)].stats.timeouts += 1
        update()
    }

    func recordStrike(station: Int, player: Int) {
        players[playerIndex(station, player)].stats.strikes += 1
        emit(.strike(station: station, player: player))
    }

    func randomIndex(_ count: Int) -> Int { Int.random(in: 0..<count, using: &rng) }

    func randomDelay() -> TimeInterval {
        switch definition.lightDelay {
        case .none: return LightDelay.noneGap
        case .fixed(let s): return s
        case .random(let from, let to):
            guard from < to else { return from }
            // The original draws whole steps between from and to; seconds with 0.5 s steps here.
            let steps = Int(((to - from) / 0.5).rounded())
            return from + Double(Int.random(in: 0...steps, using: &rng)) * 0.5
        }
    }

    @discardableResult
    func after(_ delay: TimeInterval, _ action: @escaping () -> Void) -> DrillTimer {
        let t = scheduler.schedule(after: delay, action)
        sessionTimers.append(t)
        return t
    }

    func update() { onUpdate?() }

    // MARK: Helpers

    private func emit(_ event: DrillEvent) {
        onEvent?(event)
        update()
    }

    private func allOff() { litPods.keys.sorted().forEach(off) }

    private func cancelSessionTimers() {
        sessionTimers.forEach { $0.cancel() }
        sessionTimers.removeAll()
    }

    private func playerIndex(_ station: Int, _ player: Int) -> Int {
        station * definition.playersPerStation + player
    }
}

// MARK: - Station engines

class StationEngine {
    let station: Int
    let pods: [Int]
    unowned let session: DrillSession
    private(set) var isDone = false
    private var timers: [DrillTimer] = []

    init(station: Int, pods: [Int], session: DrillSession) {
        self.station = station
        self.pods = pods
        self.session = session
    }

    var def: DrillDefinition { session.definition }

    func start() { isDone = false }

    func stop() {
        isDone = true
        timers.forEach { $0.cancel() }
        timers.removeAll()
        pods.forEach(session.off)
    }

    func handleHit(pod: Int, reactionMs: Int) {}

    func finish() { session.stationFinished(self) }

    /// True when the hit target for the cycle is reached.
    func reachedHitTarget(_ hitsThisCycle: Int) -> Bool {
        guard let target = def.duration.hits else { return false }
        return hitsThisCycle >= target
    }

    @discardableResult
    func after(_ delay: TimeInterval, _ action: @escaping () -> Void) -> DrillTimer {
        let t = session.scheduler.schedule(after: delay) { [weak self] in
            guard let self, !self.isDone else { return }
            action()
        }
        timers.append(t)
        timers.removeAll { $0.isCancelled }
        return t
    }

    func randomColor(_ colors: [PodColor]) -> PodColor {
        colors.isEmpty ? .default : colors[session.randomIndex(colors.count)]
    }

    /// Random pod from `candidates`, avoiding `previous` when there is a choice (`ee.a.g`).
    func randomPod(from candidates: [Int], avoiding previous: Int?) -> Int? {
        guard !candidates.isEmpty else { return nil }
        var pool = candidates
        if let previous, pool.count > 1 { pool.removeAll { $0 == previous } }
        return pool[session.randomIndex(pool.count)]
    }
}

/// Random engine (`g8.l`): regular = each player independently; first-to-hit = shared rounds.
final class RandomStation: StationEngine {
    private struct Slot {
        var pod: Int?
        var previous: Int?
        var waiting = false
        var timeout: DrillTimer?
    }

    private var slots: [Slot] = []
    private var roundTimeout: DrillTimer?

    private var firstToHit: Bool { def.competition == .firstToHit && def.players > 1 }

    override func start() {
        super.start()
        slots = Array(repeating: Slot(), count: def.players)
        if firstToHit { startRound() } else { (0..<def.players).forEach(assign) }
    }

    override func stop() {
        slots.indices.forEach { slots[$0].timeout?.cancel(); slots[$0].pod = nil }
        roundTimeout?.cancel()
        super.stop()
    }

    private func colors(_ player: Int) -> [PodColor] { def.colors(forPlayer: player) }

    // Regular mode

    private func assign(_ player: Int) {
        let used = Set(slots.compactMap(\.pod))
        let free = pods.filter { !used.contains($0) }
        // With a light delay the original releases the pod first, so it may come up again.
        let avoid = def.lightDelay == .none ? slots[player].previous : nil
        guard let pod = randomPod(from: free, avoiding: avoid) else { return }
        slots[player].pod = pod
        slots[player].waiting = false
        session.light(pod, randomColor(colors(player)), offOnHit: def.lightsOut.endsOnHit)
        if def.lightsOut.endsOnTimeout {
            slots[player].timeout = after(def.lightsOutTimeout) { [weak self] in self?.timedOut(player) }
        }
        session.update()
    }

    private func release(_ player: Int) {
        slots[player].timeout?.cancel()
        if let pod = slots[player].pod { session.off(pod) }
        slots[player].previous = slots[player].pod
        slots[player].pod = nil
        slots[player].waiting = true
        after(session.randomDelay()) { [weak self] in self?.assign(player) }
    }

    private func timedOut(_ player: Int) {
        guard slots[player].pod != nil else { return }
        if def.lightsOut == .timeout {
            session.recordTimeout(station: station, player: player)
        } else {
            session.recordMiss(station: station, player: player)
        }
        release(player)
    }

    // First-to-hit mode

    private func startRound() {
        var free = pods
        for p in slots.indices {
            guard let pod = randomPod(from: free, avoiding: slots[p].previous) else { continue }
            free.removeAll { $0 == pod }
            slots[p].pod = pod
            slots[p].waiting = false
            // Off-on-hit is disabled here: the losing pods must stay lit until the round ends.
            session.light(pod, randomColor(colors(p)), offOnHit: false)
        }
        if def.lightsOut.endsOnTimeout {
            roundTimeout = after(def.lightsOutTimeout) { [weak self] in self?.roundTimedOut() }
        }
        session.update()
    }

    private func endRound() {
        roundTimeout?.cancel()
        for p in slots.indices {
            if let pod = slots[p].pod { session.off(pod) }
            slots[p].previous = slots[p].pod
            slots[p].pod = nil
            slots[p].waiting = true
        }
        after(session.randomDelay()) { [weak self] in self?.startRound() }
    }

    private func roundTimedOut() {
        for p in slots.indices where slots[p].pod != nil {
            if def.lightsOut == .timeout {
                session.recordTimeout(station: station, player: p)
            } else {
                session.recordMiss(station: station, player: p)
            }
        }
        endRound()
    }

    override func handleHit(pod: Int, reactionMs: Int) {
        guard !isDone, def.lightsOut.endsOnHit,
              let player = slots.firstIndex(where: { $0.pod == pod && !$0.waiting }) else { return }
        let hits = session.recordHit(station: station, player: player, reactionMs: reactionMs)
        if firstToHit {
            for p in slots.indices where p != player && slots[p].pod != nil {
                session.recordMiss(station: station, player: p)
            }
        }
        if reachedHitTarget(hits) { return finish() }
        firstToHit ? endRound() : release(player)
    }
}

/// Focus engine (`g8.d`): one target in the player's colour plus distracting pods.
final class FocusStation: StationEngine {
    private var target: Int?
    private var previousTarget: Int?
    private var distractors: Set<Int> = []
    private var lit = false
    private var timeout: DrillTimer?
    private var cycleStrikes = 0

    override func start() {
        super.start()
        cycleStrikes = 0
        target = nil
        previousTarget = nil
        showRound()
    }

    override func stop() {
        timeout?.cancel()
        lit = false
        target = nil
        distractors = []
        super.stop()
    }

    private func showRound() {
        guard let t = randomPod(from: pods, avoiding: previousTarget) else { return }
        target = t
        var free = pods.filter { $0 != t }
        distractors = []
        for _ in 0..<min(def.distractingPods, free.count) {
            let pod = free.remove(at: session.randomIndex(free.count))
            distractors.insert(pod)
        }
        session.light(t, randomColor(def.colors(forPlayer: 0)), offOnHit: false)
        for pod in distractors.sorted() {
            session.light(pod, randomColor(def.distractingColors), offOnHit: false)
        }
        lit = true
        if def.lightsOut.endsOnTimeout {
            timeout = after(def.lightsOutTimeout) { [weak self] in self?.timedOut() }
        }
        session.update()
    }

    private func clearRound() {
        timeout?.cancel()
        lit = false
        if let target { session.off(target) }
        distractors.forEach(session.off)
        previousTarget = target
        target = nil
        distractors = []
        after(session.randomDelay()) { [weak self] in self?.showRound() }
    }

    private func timedOut() {
        guard lit else { return }
        session.recordMiss(station: station, player: 0)
        clearRound()
    }

    override func handleHit(pod: Int, reactionMs: Int) {
        guard !isDone, lit else { return }
        if pod == target {
            let hits = session.recordHit(station: station, player: 0, reactionMs: reactionMs)
            if reachedHitTarget(hits) { return finish() }
            clearRound()
        } else if distractors.contains(pod) {
            session.recordStrike(station: station, player: 0)
            cycleStrikes += 1
            if let limit = def.strikeOut, cycleStrikes >= limit { finish() }
        }
    }
}
